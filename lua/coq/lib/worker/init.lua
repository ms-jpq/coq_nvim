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

local MODE = {
  STREAM = "stream",
  RPC = "rpc",
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

local frame_to_result = function(frame)
  if frame.ok then
    return nil, unpack(frame.values, 1, frame.n)
  end
  return frame.values[1] or errs.UNKNOWN
end

local M = {}

M.streaming = function(fn)
  return { streaming = true, fn = fn }
end

local is_streaming = function(decl)
  return type(decl) == "table" and decl.streaming == true
end

local make_endpoint = function(duplex, invoker)
  local enter = not vim.is_thread() and vim.schedule or nil
  local endpoint = {}

  endpoint.flights = inflight.new()
  local parked = inflight.new()

  local write = transport.writer(duplex.writer)

  local open = function(body)
    local handle = async.current()
    local f = async.future()
    local id, release = endpoint.flights.reserve(function(frame)
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

  endpoint.request = function(body)
    local frame = open(body).next()
    if frame == nil then
      return errs.UNKNOWN
    end
    return frame_to_result(frame)
  end

  endpoint.request_stream = function(method, args, argn)
    local session = open { method = method, args = args, argn = argn }
    local it = { close = session.close }
    local next = function()
      local frame = session.next()
      if not frame then
        return nil
      end
      if frame.ok == nil then
        return unpack(frame.values, 1, frame.n)
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

  endpoint.handlers = {
    [Kind.YIELD] = dispatch(endpoint.flights),
    [Kind.NEXT] = dispatch(parked),
    [Kind.STOP] = dispatch(parked),
    [Kind.REQUEST] = function(frame)
      if enter then
        local f = async.future()
        enter(f.resolve)
        f.await(async.current())
      end
      local yield = function(...)
        local argn, args = select("#", ...), { ... }
        write { kind = Kind.YIELD, id = frame.id, n = argn, values = args }
        local fu = async.future()
        local release
        _, release = parked.reserve(function(rsp)
          release()
          fu.resolve(rsp.kind == Kind.NEXT)
        end, frame.id)
        return fu.await(async.current())
      end
      local ok, n, vals = invoker(frame, yield)
      write { kind = Kind.YIELD, id = frame.id, ok = ok, n = n, values = vals }
    end,
  }

  return endpoint
end

M.spawn = function(definition)
  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    local fn, err = load(frame.fn_dump)
    if not fn then
      return pack(false, err or errs.UNKNOWN)
    end
    return pack(pcall(fn, unpack(frame.args or {}, 1, frame.argn or 0)))
  end)

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
    endpoint.flights.drain {
      kind = Kind.YIELD,
      ok = false,
      n = 1,
      values = { "worker died" },
    }
    exited.resolve()
  end))

  transport.spawn_worker(function(read_fd, write_fd, bytes)
    require("coq.lib.worker").run(read_fd, write_fd, vim.mpack.decode(bytes))
  end, remote.read_fd, remote.write_fd, config.encode(definition))

  local bind_rpc = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return unwrap(endpoint.request {
        method = name,
        args = { ... },
        argn = select("#", ...),
      })
    end
  end

  local bind_stream = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return endpoint.request_stream(name, { ... }, select("#", ...))
    end
  end

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
      proxy[name] = is_streaming(decl) and bind_stream(name) or bind_rpc(name)
    end
  end

  return proxy
end

M.run = function(req_fd, rsp_fd, raw)
  local duplex = transport.open_duplex(req_fd, rsp_fd)
  local state, methods = config.decode(raw)

  local endpoint = make_endpoint(duplex, function(frame, yield)
    local m = methods[frame.method]
    if not m then
      return pack(false, "unknown method: " .. tostring(frame.method))
    end
    local args, argn = frame.args or {}, frame.argn or 0
    if m.mode == MODE.STREAM then
      return pack(pcall(m.fn, yield, state, unpack(args, 1, argn)))
    end
    return pack(pcall(m.fn, state, unpack(args, 1, argn)))
  end)

  M.main = function(fn, ...)
    return unwrap(endpoint.request {
      fn_dump = string.dump(fn),
      args = { ... },
      argn = select("#", ...),
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
