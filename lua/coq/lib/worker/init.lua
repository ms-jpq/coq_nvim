-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config_proto"
local errs = require "coq.lib.errs"
local inflight = require "coq.lib.worker.inflight"
local proto = require "coq.lib.worker.wire_proto"

local Kind = {
  REQUEST = "request",
  RESPONSE = "response",
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

local open_duplex = function(read_fd, write_fd)
  local duplex = {}
  duplex.reader, duplex.writer = vim.uv.new_pipe(), vim.uv.new_pipe()
  duplex.reader:open(read_fd)
  duplex.writer:open(write_fd)

  duplex.close = function()
    duplex.writer:shutdown(function()
      duplex.writer:close()
    end)
  end
  return duplex
end

local duplex_pair = function()
  local inbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local outbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })

  local duplex = open_duplex(inbound.read, outbound.write)
  local remote = {}
  remote.read_fd = outbound.read
  remote.write_fd = inbound.write
  return duplex, remote
end

-- A RESPONSE-shaped frame as (err, value1, value2, ...). `err` is nil on
-- success. Pairs with `pack` on the other end.
local frame_to_result = function(frame)
  if frame.ok then
    return nil, unpack(frame.values, 1, frame.n)
  end
  return frame.values[1] or errs.UNKNOWN
end

local sender = function(pipe)
  return function(body)
    pipe:write(proto.encode(body))
  end
end

local responder = function(send, kind)
  return function(id, ok, n, vals)
    send { kind = kind, id = id, ok = ok, n = n, values = vals }
  end
end

local start_reader = function(pipe, handlers, on_eof)
  local decode = proto.decoder()
  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      on_eof()
      return
    end
    for frame in decode(data) do
      handlers[frame.kind](frame)
    end
  end)
end

local M = {}

-- Marker for streaming method declarations.
M.streaming = function(fn)
  return { streaming = true, fn = fn }
end

local is_streaming = function(decl)
  return type(decl) == "table" and decl.streaming == true
end

-- Symmetric RPC endpoint. Each side holds one of these — same shape, same
-- wire conventions. Streaming outbound (`iter_call`) is included so both sides
-- share the YIELD wire convention; worker-side `iter_call` just goes unused
-- today. Side-specific inbound kinds (NEXT/STOP on worker) are layered onto
-- `base_handlers` by the caller via `vim.tbl_extend`.
local make_endpoint = function(duplex, invoker, opts)
  opts = opts or {}
  local schedule = opts.schedule or function(thunk)
    thunk()
  end

  local flights = inflight.new()

  local send = sender(duplex.writer)
  local respond = responder(send, Kind.RESPONSE)

  local request = function(body)
    local f = async.future()
    local id, release
    id, release = flights.reserve(function(frame)
      release()
      f.resolve(frame_to_result(frame))
    end)
    body.kind, body.id = Kind.REQUEST, id
    send(body)
    return f.await()
  end

  local iter_call = function(method, args, argn)
    local f = async.future()
    local id, release = flights.reserve(function(frame)
      f.resolve(frame)
    end)
    send { kind = Kind.REQUEST, id = id, method = method, args = args, argn = argn }

    local done, first = false, true
    local it = {}

    it.close = function()
      if done then
        return
      end
      done = true
      send { kind = Kind.STOP, id = id }
      release()
    end

    local next = function()
      if done then
        return nil
      end

      if not first then
        f = async.future()
        send { kind = Kind.NEXT, id = id }
      end
      first = false

      local frame = f.await()
      if frame.kind == Kind.YIELD then
        return unpack(frame.values, 1, frame.n)
      end
      done = true

      release()
      if not frame.ok then
        error(frame.values[1] or errs.UNKNOWN, 2)
      end
      return nil
    end

    return setmetatable(it, { __call = next })
  end

  local base_handlers = {
    [Kind.RESPONSE] = flights.resolve,
    [Kind.YIELD] = flights.resolve,
    [Kind.REQUEST] = function(frame)
      local id = frame.id
      schedule(async.thunk(function()
        respond(id, invoker(frame))
      end))
    end,
  }

  return {
    duplex = duplex,
    send = send,
    respond = respond,
    flights = flights,
    request = request,
    iter_call = iter_call,
    base_handlers = base_handlers,
  }
end

-- Main-side dispatch: load the dumped fn from a reverse-RPC request and pcall
-- it. Mirrors the worker-side `invoke` shape — returns (ok, n, vals) ready
-- for `respond`.
local invoke_main = function(fn_dump, args, argn)
  local fn, err = load(fn_dump)
  if not fn then
    return pack(false, err or errs.UNKNOWN)
  end
  return pack(pcall(fn, unpack(args, 1, argn)))
end

-- Main-side: spawn a worker. Returns a proxy table with the worker's methods
-- bound, plus `close` to tear it down.
M.spawn = function(definition)
  local duplex, remote = duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    return invoke_main(frame.fn_dump, frame.args or {}, frame.argn or 0)
  end, { schedule = vim.schedule })

  local exited = async.future()
  start_reader(duplex.reader, endpoint.base_handlers, function()
    endpoint.flights.drain "worker died"
    exited.resolve()
  end)

  vim.uv.new_thread(function(req_fd, rsp_fd, bootstrap)
    require("coq.lib.worker").run(req_fd, rsp_fd, vim.mpack.decode(bootstrap))
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
      return endpoint.iter_call(name, { ... }, select("#", ...))
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

-- Worker-side dispatch loop. Entry point invoked from `vim.uv.new_thread`
-- in `M.spawn` above. Runs in its own Lua state with its own libuv loop.
M.run = function(req_fd, rsp_fd, raw)
  local duplex = open_duplex(req_fd, rsp_fd)
  local state, methods = config.decode(raw)
  local iter_resumers = {}

  local endpoint
  local make_yield, invoke, resume_iter

  endpoint = make_endpoint(duplex, function(frame)
    return invoke(frame.method, frame.id, frame.args or {}, frame.argn or 0)
  end)

  make_yield = function(id)
    return function(...)
      local argn, args = select("#", ...), { ... }
      endpoint.send { kind = Kind.YIELD, id = id, n = argn, values = args }
      local f = async.future()
      iter_resumers[id] = f.resolve
      return f.await()
    end
  end

  invoke = function(name, id, args, argn)
    local m = methods[name]
    if not m then
      return pack(false, "unknown method: " .. tostring(name))
    end
    if m.mode == MODE.STREAM then
      return pack(pcall(m.fn, make_yield(id), state, unpack(args, 1, argn)))
    end
    return pack(pcall(m.fn, state, unpack(args, 1, argn)))
  end

  resume_iter = function(value)
    return function(frame)
      local r = iter_resumers[frame.id]
      iter_resumers[frame.id] = nil
      if r then
        r(value)
      end
    end
  end

  local handlers = vim.tbl_extend("error", endpoint.base_handlers, {
    [Kind.NEXT] = resume_iter(true),
    [Kind.STOP] = resume_iter(false),
  })

  -- Exposed on the worker's module so user methods running here can call
  -- back to the main process: `require("coq.lib.worker").main(fn, ...)`.
  M.main = function(fn, ...)
    return unwrap(endpoint.request {
      fn_dump = string.dump(fn),
      args = { ... },
      argn = select("#", ...),
    })
  end

  start_reader(duplex.reader, handlers, duplex.close)
  vim.uv.run()
end

return M
