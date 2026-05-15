local async = require "coq.lib.async"
local config = require "coq.lib.worker.config_proto"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local inflight = require "coq.lib.worker.inflight"
local mpmc = require "coq.lib.channels.mpmc"
local runtime = require "coq.lib.async.runtime"
local transport = require "coq.lib.worker.frame_transport"

local Kind = {
  REQUEST = "request",
  YIELD = "yield",
  NEXT = "next",
  STOP = "stop",
}

local pack_frame = function(ok, ...)
  return ok, select("#", ...), { ... }
end

local unwrap = function(err, ...)
  if err then
    error(err, 3)
  end
  return ...
end

local M = {}

M.streaming = config.streaming

local make_endpoint = function(duplex, invoker)
  local endpoint = {}

  local flights = inflight.new()
  local parked = inflight.new()
  endpoint.drain = flights.drain

  local write = transport.writer(duplex.writer)

  local open = function(message)
    local chan = mpmc.new(1)
    local id, release = flights.reserve(chan.push)

    message.kind, message.id = Kind.REQUEST, id
    write(message)

    local first, done = true, false

    local session = {}

    session.next = function()
      if done then
        return nil
      end

      if first then
        first = false
      else
        write { kind = Kind.NEXT, id = id }
      end

      local frame = chan.pull()
      if frame == nil then
        write { kind = Kind.STOP, id = id }
      end
      if frame == nil or frame.ok ~= nil then
        release()
        chan.close()
        done = true
      end
      return frame
    end

    session.close = function()
      if done then
        return
      end
      done = true
      write { kind = Kind.STOP, id = id }
      release()
      chan.close()
    end

    return session
  end

  endpoint.request_oneshot = function(message)
    local session = open(message)
    local frame = session.next()
    if frame == nil then
      return
    end
    if frame.ok then
      return nil, unpack(frame.values, 1, frame.n_values)
    end
    return frame.values[1] or errs.UNKNOWN
  end

  endpoint.request_stream = function(message)
    local session = open(message)
    local it = { close = session.close }
    local next = function()
      local frame = session.next()
      if not frame then
        return nil
      end
      if frame.ok == nil then
        return unpack(frame.values, 1, frame.n_values)
      end
      if not frame.ok then
        error(frame.values[1] or errs.UNKNOWN, 2)
      end
      return nil
    end

    return setmetatable(it, { __call = next })
  end

  local to_tracker = function(tracker)
    return function(frame)
      tracker.resolve(frame.id, frame)
    end
  end

  local make_control = function(id, req_handle)
    local controls = mpmc.new()
    local stopped = false
    local _, release = parked.reserve(function(rsp)
      if rsp.kind == Kind.STOP then
        stopped = true
        req_handle.cancel()
      end
      controls.push(rsp.kind == Kind.NEXT)
    end, id)

    local yield_fn = function(...)
      if select("#", ...) == 0 then
        error("yield: at least one value required", 2)
      end
      if stopped then
        return false
      end
      local n_values, values = select("#", ...), { ... }
      write { kind = Kind.YIELD, id = id, n_values = n_values, values = values }
      local v = controls.pull()
      if not v then
        stopped = true
      end
      return v
    end

    return yield_fn, release
  end

  local enter_async = vim.is_thread() and function() end or require("coq.lib.async.vim").scheduled
  local handlers = {
    [Kind.YIELD] = to_tracker(flights),
    [Kind.NEXT] = to_tracker(parked),
    [Kind.STOP] = to_tracker(parked),
  }

  endpoint.dispatch = function(n, frame)
    if frame.kind ~= Kind.REQUEST then
      n.spawn(function()
        handlers[frame.kind](frame)
      end)
      return
    end

    local req_handle = handle.new(runtime.current())
    local yield_fn, release = make_control(frame.id, req_handle)

    n.spawn(function()
      runtime.bind(coroutine.running(), req_handle)
      enter_async()
      local ok, n_values, values = invoker(frame, yield_fn)
      release()
      req_handle.cancel()
      write {
        kind = Kind.YIELD,
        id = frame.id,
        ok = ok,
        n_values = n_values,
        values = values,
      }
    end)
  end

  return endpoint
end

M.spawn = function(definition)
  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return pack_frame(false, err or errs.UNKNOWN)
    end
    return pack_frame(pcall(fn, unpack(frame.args or {}, 1, frame.n_args or 0)))
  end)

  transport.spawn_worker(function(...)
    require("coq.lib.worker").run(...)
  end, remote.read_fd, remote.write_fd, config.encode(definition))

  local bind_oneshot = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return unwrap(endpoint.request_oneshot {
        method = name,
        args = { ... },
        n_args = select("#", ...),
      })
    end
  end

  local bind_stream = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return endpoint.request_stream {
        method = name,
        args = { ... },
        n_args = select("#", ...),
      }
    end
  end

  do
    local proxy = {}

    for name, decl in pairs(definition) do
      if name ~= "init" then
        proxy[name] = config.is_streaming(decl) and bind_stream(name) or bind_oneshot(name)
      end
    end

    local n = async.nursery()
    n.spawn(function()
      for frame in transport.reader(duplex.reader) do
        endpoint.dispatch(n, frame)
      end
      endpoint.drain {
        kind = Kind.YIELD,
        ok = false,
        n_values = 1,
        values = { "worker died" },
      }
    end)

    proxy.close = function()
      if not closed then
        closed = true
        duplex.close()
      end

      n.join()
    end

    return proxy
  end
end

M.run = function(req_fd, rsp_fd, bytes)
  local duplex = transport.open_duplex(req_fd, rsp_fd)
  local state, methods = config.decode(vim.mpack.decode(bytes))

  local endpoint = make_endpoint(duplex, function(frame, yield)
    local m = methods[frame.method]
    if not m then
      return pack_frame(false, "unknown method: " .. tostring(frame.method))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    if m.streaming then
      return pack_frame(pcall(m.fn, yield, state, unpack(args, 1, n_args)))
    end
    return pack_frame(pcall(m.fn, state, unpack(args, 1, n_args)))
  end)

  M.main = function(fn, ...)
    return unwrap(endpoint.request_oneshot {
      fn_bytecode = string.dump(fn),
      args = { ... },
      n_args = select("#", ...),
    })
  end

  async.thunk(function()
    async.scope(function(n, defer)
      defer(duplex.close)
      defer(n.handle.cancel)

      for frame in transport.reader(duplex.reader) do
        endpoint.dispatch(n, frame)
      end
    end)
  end)()

  vim.uv.run()
end

return M
