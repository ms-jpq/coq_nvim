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

local responder = function(write, kind)
  return function(id, ok, n, vals)
    write { kind = kind, id = id, ok = ok, n = n, values = vals }
  end
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
  local schedule = opts.schedule or function(thunk)
    thunk()
  end

  local flights = inflight.new()

  local write = transport.writer(duplex.writer)
  local respond = responder(write, Kind.RESPONSE)

  -- A request session: open, then read frames via `next` until terminal
  -- RESPONSE (which auto-releases the slot), or end early via `close`
  -- (sends K.STOP). The reserve callback resumes the consumer directly with
  -- the frame; `next` is just `coroutine.yield`.
  --
  -- One-shot RPC is just one `next` call; iteration is many.
  local open_session = function(body)
    local thread = coroutine.running()
    local id, release
    id, release = flights.reserve(function(frame)
      coroutine.resume(thread, frame)
    end)
    body.kind, body.id = Kind.REQUEST, id
    write(body)

    local done, first = false, true
    local session = {}

    session.next = function()
      if done then
        return nil
      end
      assert(coroutine.running() == thread, "session.next called from a different coroutine")

      if first then
        first = false
      else
        write { kind = Kind.NEXT, id = id }
      end

      local frame = coroutine.yield()
      if frame.kind ~= Kind.YIELD then
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
  -- and return it as `(err, values...)`.
  local request = function(body)
    return frame_to_result(open_session(body).next())
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

  local base_handlers = {
    [Kind.RESPONSE] = flights.resolve,
    [Kind.YIELD] = flights.resolve,
    [Kind.REQUEST] = function(frame)
      local id = frame.id
      schedule(function()
        local co = coroutine.create(function()
          respond(id, invoker(frame))
        end)
        local ok, err = coroutine.resume(co)
        if not ok then
          error(err, 0)
        end
      end)
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
  end, { schedule = vim.schedule })

  local exited = async.future()
  coroutine.resume(coroutine.create(function()
    for frame in transport.reader(duplex.reader) do
      endpoint.base_handlers[frame.kind](frame)
    end
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
    local thread = coroutine.running()
    return function(...)
      assert(coroutine.running() == thread, "yield called from a different coroutine")
      local argn, args = select("#", ...), { ... }
      endpoint.send { kind = Kind.YIELD, id = id, n = argn, values = args }
      iter_resumers[id] = thread
      return coroutine.yield()
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
      local thread = iter_resumers[frame.id]
      iter_resumers[frame.id] = nil
      if thread then
        coroutine.resume(thread, value)
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

  coroutine.resume(coroutine.create(function()
    for frame in transport.reader(duplex.reader) do
      handlers[frame.kind](frame)
    end
    duplex.close()
  end))

  vim.uv.run()
end

return M
