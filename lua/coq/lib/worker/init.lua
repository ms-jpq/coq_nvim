local async = require "coq.lib.async"
local config = require "coq.lib.worker.config_proto"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local inflight = require "coq.lib.worker.inflight"
local mpmc = require "coq.lib.channels.mpmc"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"
local transport = require "coq.lib.worker.frame_transport"

local Kind = {
  REQUEST = "request",
  YIELD = "yield",
  NEXT = "next",
  STOP = "stop",
}

local STATE = {
  INITIAL = "initial",
  STREAMING = "streaming",
  DONE = "done",
}

local response = function(id, ok, ...)
  return {
    kind = Kind.YIELD,
    id = id,
    ok = ok,
    n_values = select("#", ...),
    values = { ... },
  }
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
    local ok, err = pcall(write, message)
    if not ok then
      release()
      chan.close()
      error(err, 0)
    end

    local state = STATE.INITIAL
    local session = {}
    local unwatch

    local cleanup = function()
      state = STATE.DONE
      if unwatch then
        unwatch()
        unwatch = nil
      end
      release()
      chan.close()
    end

    session.next = function()
      if state == STATE.DONE then
        return nil
      end

      if state == STATE.STREAMING then
        write { kind = Kind.NEXT, id = id }
      end

      local frame = chan.pull()
      if frame == nil then
        write { kind = Kind.STOP, id = id }
      end
      if frame == nil or frame.ok ~= nil then
        cleanup()
      else
        state = STATE.STREAMING
      end
      return frame
    end

    session.close = function()
      if state == STATE.DONE then
        return
      end
      write { kind = Kind.STOP, id = id }
      cleanup()
    end

    unwatch = runtime.current().on_cancel(session.close)

    return session
  end

  endpoint.request_oneshot = function(message)
    local session = open(message)
    local frame = session.next()
    if frame == nil then
      return
    end
    if frame.ok then
      return unpack(frame.values, 1, frame.n_values)
    end
    error(frame.values[1] or errs.UNKNOWN, 3)
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

  local make_yield = function(id, req_handle)
    local chan = mpmc.new()
    local _, release = parked.reserve(function(rsp)
      if rsp.kind == Kind.STOP then
        req_handle.cancel()
      else
        chan.push(true)
      end
    end, id)

    req_handle.on_cancel(function()
      release()
      chan.push(false)
    end)

    local yield_fn = function(...)
      if req_handle.cancelled then
        return false
      end
      local n_values, values = select("#", ...), { ... }
      assert(n_values > 0, "yield: at least one value required")
      for i = 1, n_values do
        assert(values[i] ~= nil, "yield: nil value at position " .. i)
      end
      write { kind = Kind.YIELD, id = id, n_values = n_values, values = values }
      return chan.pull()
    end

    return yield_fn
  end

  local scheduled = vim.is_thread() and function() end or require("coq.lib.async.vim").scheduled
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
    local yield_fn = make_yield(frame.id, req_handle)

    n.spawn(function(defer)
      defer(req_handle.cancel)
      runtime.bind(coroutine.running(), req_handle)
      scheduled()
      write(invoker(frame, yield_fn))
    end)
  end

  return endpoint
end

M.spawn = function(definition)
  assert(definition.close == nil, "worker.spawn: 'close' is reserved by the proxy")

  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return response(frame.id, false, err or errs.UNKNOWN)
    end
    return response(frame.id, pcall(fn, unpack(frame.args or {}, 1, frame.n_args or 0)))
  end)

  transport.spawn_worker(function(...)
    require("coq.lib.worker").run(...)
  end, remote.read_fd, remote.write_fd, config.encode(definition))

  local bind = function(request, name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return request {
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
        local request = config.is_streaming(decl) and endpoint.request_stream or endpoint.request_oneshot
        proxy[name] = bind(request, name)
      end
    end

    local n = nursery.new()
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
      return response(frame.id, false, "unknown method: " .. tostring(frame.method))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    if m.streaming then
      return response(frame.id, pcall(m.fn, yield, state, unpack(args, 1, n_args)))
    end
    return response(frame.id, pcall(m.fn, state, unpack(args, 1, n_args)))
  end)

  M.main = function(fn, ...)
    return endpoint.request_oneshot {
      fn_bytecode = string.dump(fn),
      args = { ... },
      n_args = select("#", ...),
    }
  end

  async.thunk(function()
    async.scope(function(n, defer)
      defer(duplex.close)

      for frame in transport.reader(duplex.reader) do
        endpoint.dispatch(n, frame)
      end
    end)
  end)()

  vim.uv.run()
end

return M
