local async = require "coq.lib.async"
local config = require "coq.lib.worker.config_proto"
local errs = require "coq.lib.errs"
local inflight = require "coq.lib.worker.inflight"
local transport = require "coq.lib.worker.frame_transport"

local Kind = {
  REQUEST = "request",
  YIELD = "yield",
  NEXT = "next",
  STOP = "stop",
}

local pack = function(ok, ...)
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

  local open = function(body)
    local handle = async.current()
    local f = async.future()
    local id, release = flights.reserve(function(frame)
      f.resolve(frame)
    end)

    body.kind, body.id = Kind.REQUEST, id
    write(body)

    local first = true

    local session = {}

    session.next = function()
      if not f then
        return nil
      end

      if first then
        first = false
      else
        f = async.future()
        write { kind = Kind.NEXT, id = id }
      end

      local frame = f.await(handle)
      if frame == nil or frame.ok ~= nil then
        release()
        f = nil
      end
      return frame
    end

    session.close = function()
      if not f then
        return
      end
      write { kind = Kind.STOP, id = id }
      release()
      f = nil
    end

    return session
  end

  endpoint.request_oneshot = function(message)
    local frame = open(message).next()
    if frame == nil then
      return errs.UNKNOWN
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

  local dispatch = function(tracker)
    return function(frame)
      tracker.resolve(frame.id, frame)
    end
  end

  local park = function(id)
    local f = async.future()
    local release
    _, release = parked.reserve(function(rsp)
      release()
      f.resolve(rsp.kind == Kind.NEXT)
    end, id)

    return f.await(async.current())
  end

  local make_yield = function(id)
    return function(...)
      local n_values, values = select("#", ...), { ... }
      write { kind = Kind.YIELD, id = id, n_values = n_values, values = values }
      return park(id)
    end
  end

  local enter_async = vim.is_thread() and function() end or require("coq.lib.async.vim").scheduled
  endpoint.handlers = {
    [Kind.YIELD] = dispatch(flights),
    [Kind.NEXT] = dispatch(parked),
    [Kind.STOP] = dispatch(parked),
    [Kind.REQUEST] = function(frame)
      enter_async()
      local ok, n_values, values = invoker(frame, make_yield(frame.id))
      write {
        kind = Kind.YIELD,
        id = frame.id,
        ok = ok,
        n_values = n_values,
        values = values,
      }
    end,
  }

  return endpoint
end

M.spawn = function(definition)
  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return pack(false, err or errs.UNKNOWN)
    end
    return pack(pcall(fn, unpack(frame.args or {}, 1, frame.n_args or 0)))
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

  local exited = async.future()

  coroutine.resume(coroutine.create(function()
    async.scope(function(n, defer)
      defer(n.handle.cancel)
      for frame in transport.reader(duplex.reader) do
        n.spawn(function()
          endpoint.handlers[frame.kind](frame)
        end)
      end
    end)

    endpoint.drain {
      kind = Kind.YIELD,
      ok = false,
      n_values = 1,
      values = { "worker died" },
    }
    exited.resolve()
  end))

  do
    local proxy = {
      close = function()
        if not closed then
          closed = true
          duplex.close()
        end

        exited.await()
      end,
    }

    for name, decl in pairs(definition) do
      if name ~= "init" then
        proxy[name] = config.is_streaming(decl) and bind_stream(name) or bind_oneshot(name)
      end
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
      return pack(false, "unknown method: " .. tostring(frame.method))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    if m.streaming then
      return pack(pcall(m.fn, yield, state, unpack(args, 1, n_args)))
    end
    return pack(pcall(m.fn, state, unpack(args, 1, n_args)))
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
        n.spawn(function()
          endpoint.handlers[frame.kind](frame)
        end)
      end
    end)
  end)()

  vim.uv.run()
end

return M
