local async = require "coq.lib.async"
local config = require "coq.lib.worker.config_proto"
local errs = require "coq.lib.errs"
local inflight = require "coq.lib.worker.inflight"
local transport = require "coq.lib.worker.frame_transport"

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

-- A RESPONSE-shaped frame as (err, value1, value2, ...). `err` is nil on
-- success. Pairs with `pack` on the other end.
local frame_to_result = function(frame)
  if frame.ok then
    return nil, unpack(frame.values, 1, frame.n)
  end
  return frame.values[1] or errs.UNKNOWN
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
  local enter = opts.enter

  local flights = inflight.new()

  local write = transport.writer(duplex.writer)
  local respond = function(id, ok, n, vals)
    write { kind = Kind.RESPONSE, id = id, ok = ok, n = n, values = vals }
  end

  -- A request session: open, then read frames via `next` until terminal
  -- RESPONSE (which auto-releases the slot), or end early via `close`
  -- (sends K.STOP). Awaits use the current async handle so EOF / scope
  -- cancellation unblocks them; a cancelled `next` returns nil.
  --
  -- One-shot RPC is just one `next` call; iteration is many.
  local open_session = function(body)
    local handle = async.current()
    local f = async.future()
    local id, release
    id, release = flights.reserve(function(frame)
      f.resolve(frame)
    end)
    body.kind, body.id = Kind.REQUEST, id
    write(body)

    local done, first = false, true
    local session = {}

    session.next = function()
      if done then
        return nil
      end

      if first then
        first = false
      else
        f = async.future()
        write { kind = Kind.NEXT, id = id }
      end

      local frame = f.await(handle)
      if frame == nil or frame.kind ~= Kind.YIELD then
        done = true
        release()
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
    end

    return session
  end

  -- One-shot RPC: take the session's first (and only) frame as a RESPONSE,
  -- and return it as `(err, values...)`. A cancelled await returns the
  -- generic error.
  local request = function(body)
    local frame = open_session(body).next()
    if frame == nil then
      return errs.UNKNOWN
    end
    return frame_to_result(frame)
  end

  -- Streaming RPC: expose the session as a for-loop iterator. YIELD frames
  -- unpack to values; terminal RESPONSE returns nil (or errors).
  local iter_call = function(method, args, argn)
    local session = open_session { method = method, args = args, argn = argn }
    local it = { close = session.close }
    return setmetatable(it, {
      __call = function()
        local frame = session.next()
        if not frame then
          return nil
        end
        if frame.kind == Kind.YIELD then
          return unpack(frame.values, 1, frame.n)
        end
        if not frame.ok then
          error(frame.values[1] or errs.UNKNOWN, 2)
        end
        return nil
      end,
    })
  end

  -- The REQUEST handler runs inside a nursery-spawned coroutine. On main, it
  -- yields once via `vim.schedule` to escape libuv fast-event context before
  -- running user code. On worker, `enter` is nil and we run immediately.
  local base_handlers = {
    [Kind.RESPONSE] = flights.resolve,
    [Kind.YIELD] = flights.resolve,
    [Kind.REQUEST] = function(frame)
      if enter then
        local f = async.future()
        enter(f.resolve)
        f.await(async.current())
      end
      respond(frame.id, invoker(frame))
    end,
  }

  return {
    duplex = duplex,
    send = write,
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
  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex, function(frame)
    return invoke_main(frame.fn_dump, frame.args or {}, frame.argn or 0)
  end, { enter = vim.schedule })

  local exited = async.future()
  coroutine.resume(coroutine.create(function()
    async.scope(function(n)
      for frame in transport.reader(duplex.reader) do
        n.spawn(function()
          endpoint.base_handlers[frame.kind](frame)
        end)
      end
      n.handle.cancel()
    end)
    endpoint.flights.drain "worker died"
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

M.run = function(req_fd, rsp_fd, raw)
  local duplex = transport.open_duplex(req_fd, rsp_fd)
  local state, methods = config.decode(raw)
  local iter_resumers = {}

  local endpoint
  local make_yield, invoke, resume_iter

  endpoint = make_endpoint(duplex, function(frame)
    return invoke(frame.method, frame.id, frame.args or {}, frame.argn or 0)
  end, {})

  make_yield = function(id)
    return function(...)
      local argn, args = select("#", ...), { ... }
      endpoint.send { kind = Kind.YIELD, id = id, n = argn, values = args }
      local f = async.future()
      iter_resumers[id] = f
      return f.await(async.current())
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
      local f = iter_resumers[frame.id]
      iter_resumers[frame.id] = nil
      if f then
        f.resolve(value)
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

  async.thunk(function()
    async.scope(function(n, defer)
      defer(duplex.close)
      defer(n.handle.cancel)

      for frame in transport.reader(duplex.reader) do
        n.spawn(function()
          handlers[frame.kind](frame)
        end)
      end
    end)
  end)()

  vim.uv.run()
end

return M
