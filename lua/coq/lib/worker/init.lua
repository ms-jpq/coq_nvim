-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config"
local errs = require "coq.lib.errs"
local inflight_mod = require "coq.lib.worker.inflight"

----------------------------------------------------------------------
-- Wire protocol: 4-byte LE length prefix + mpack body.
----------------------------------------------------------------------

local HEADER_SIZE = 4
local BYTE = 256

local K = {
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

local encode = function(body)
  local payload = vim.mpack.encode(body)
  local n = #payload
  return string.char(
    n % BYTE,
    math.floor(n / BYTE) % BYTE,
    math.floor(n / (BYTE * BYTE)) % BYTE,
    math.floor(n / (BYTE * BYTE * BYTE)) % BYTE
  ) .. payload
end

local decode = function(buf)
  if #buf < HEADER_SIZE then
    return nil
  end
  local b1, b2, b3, b4 = buf:byte(1, HEADER_SIZE)
  local n = b1 + b2 * BYTE + b3 * BYTE * BYTE + b4 * BYTE * BYTE * BYTE
  if #buf < HEADER_SIZE + n then
    return nil
  end
  local decoded = vim.mpack.decode(buf:sub(HEADER_SIZE + 1, HEADER_SIZE + n))
  return decoded, buf:sub(HEADER_SIZE + n + 1)
end

local iter_decode = function(buf)
  local iter = coroutine.wrap(function()
    while true do
      local frame, rest = decode(buf)
      if not frame then
        return
      end
      coroutine.yield(frame)
      buf = rest
    end
  end)

  return iter, function()
    return buf
  end
end

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

local sender = function(pipe)
  return function(body)
    pipe:write(encode(body))
  end
end

local responder = function(send, kind)
  return function(id, ok, n, vals)
    send { kind = kind, id = id, ok = ok, n = n, values = vals }
  end
end

local start_reader = function(pipe, handlers, on_eof)
  local buf = ""
  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      on_eof()
      return
    end
    local iter, leftover = iter_decode(buf .. data)
    for frame in iter do
      handlers[frame.kind](frame)
    end
    buf = leftover()
  end)
end

----------------------------------------------------------------------
-- Worker module
----------------------------------------------------------------------

local M = {}

-- Exposed for proto.test.lua. Not part of the public worker API.
M.proto = {
  encode = encode,
  iter_decode = iter_decode,
  pack = pack,
  unwrap = unwrap,
}

-- Marker for streaming method declarations.
M.streaming = function(fn)
  return { streaming = true, fn = fn }
end

local is_streaming = function(decl)
  return type(decl) == "table" and decl.streaming == true
end

-- Main-side streaming proxy. Each call opens an inflight slot, sends the
-- request, and returns an iterator whose `__call` awaits the next K.YIELD
-- and re-arms the future for the one after.
local make_iter_call = function(send, inflight, send_request)
  return function(method, args, argn)
    local f = async.future()
    local id, release = inflight.reserve(function(frame)
      f.resolve(frame)
    end)
    send_request(id, method, args, argn)

    local done, first = false, true

    local it = {}
    it.close = function()
      if done then
        return
      end
      done = true

      send { kind = K.STOP, id = id }
      release()
    end

    local next = function()
      if done then
        return nil
      end

      if not first then
        f = async.future()
        send { kind = K.NEXT, id = id }
      end
      first = false

      local frame = f.await()
      if frame.kind == K.YIELD then
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
  local req_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local rsp_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local rsp_pipe, req_write = vim.uv.new_pipe(), vim.uv.new_pipe()
  rsp_pipe:open(rsp_fds.read)
  req_write:open(req_fds.write)

  local inflight = inflight_mod.new()
  local closed = false

  local send = sender(req_write)
  local respond_main = responder(send, K.RESPONSE)

  local handlers = {
    [K.REQUEST] = function(frame)
      local id = frame.id
      vim.schedule(async.thunk(function()
        respond_main(id, invoke_main(frame.fn_dump, frame.args or {}, frame.argn or 0))
      end))
    end,
    [K.RESPONSE] = inflight.resolve,
    [K.YIELD] = inflight.resolve,
  }

  local exited = async.future()

  start_reader(rsp_pipe, handlers, function()
    inflight.drain "worker died"
    exited.resolve()
  end)

  vim.uv.new_thread(function(req_fd, rsp_fd, bootstrap)
    require("coq.lib.worker").run(req_fd, rsp_fd, vim.mpack.decode(bootstrap))
  end, req_fds.read, rsp_fds.write, config.encode(definition))

  local send_request = function(id, method, args, argn)
    send { kind = K.REQUEST, id = id, method = method, args = args, argn = argn }
  end

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    local id, release
    id, release = inflight.reserve(function(frame)
      release()
      cb(frame_to_result(frame))
    end)
    send_request(id, method, args, argn)
  end)

  local iter_call = make_iter_call(send, inflight, send_request)

  local bind_rpc = function(name)
    return function(...)
      return unwrap(call(name, { ... }, select("#", ...)))
    end
  end

  local bind_stream = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
      return iter_call(name, { ... }, select("#", ...))
    end
  end

  local proxy = {
    close = function()
      if not closed then
        closed = true
        req_write:shutdown(function()
          req_write:close()
        end)
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

-- Reverse-RPC: build the worker's `main` entry point. Each call sends a
-- REQUEST upstream with the function's dumped bytecode and awaits the
-- response.
local make_main = function(tracker, send)
  return function(fn, ...)
    local argn, args = select("#", ...), { ... }
    local f = async.future()
    local id, release
    id, release = tracker.reserve(function(frame)
      release()
      f.resolve(frame_to_result(frame))
    end)
    send {
      kind = K.REQUEST,
      id = id,
      fn_dump = string.dump(fn),
      args = args,
      argn = argn,
    }
    return unwrap(f.await())
  end
end

-- Worker-side dispatch loop. Entry point invoked from `vim.uv.new_thread`
-- in `M.spawn` above. Runs in its own Lua state with its own libuv loop.
M.run = function(req_fd, rsp_fd, raw)
  local req_pipe, rsp_pipe = vim.uv.new_pipe(), vim.uv.new_pipe()
  req_pipe:open(req_fd)
  rsp_pipe:open(rsp_fd)

  local state, methods = config.decode(raw)
  local iter_resumers = {}
  local tracker = inflight_mod.new()

  local send = sender(rsp_pipe)
  local respond = responder(send, K.RESPONSE)

  -- Exposed on the worker's module so user methods running here can call
  -- back to the main process: `require("coq.lib.worker").main(fn, ...)`.
  M.main = make_main(tracker, send)

  local make_yield = function(id)
    return function(...)
      local argn = select("#", ...)
      local args = { ... }
      send { kind = K.YIELD, id = id, n = argn, values = args }
      local f = async.future()
      iter_resumers[id] = f.resolve
      return f.await()
    end
  end

  local invoke = function(name, id, args, argn)
    local m = methods[name]
    if not m then
      return pack(false, "unknown method: " .. tostring(name))
    end
    if m.mode == MODE.STREAM then
      return pack(pcall(m.fn, make_yield(id), state, unpack(args, 1, argn)))
    end
    return pack(pcall(m.fn, state, unpack(args, 1, argn)))
  end

  local resume_iter = function(value)
    return function(frame)
      local r = iter_resumers[frame.id]
      iter_resumers[frame.id] = nil
      if r then
        r(value)
      end
    end
  end

  local handlers = {
    [K.RESPONSE] = tracker.resolve,
    [K.REQUEST] = function(frame)
      local id = frame.id
      async.thunk(function()
        respond(id, invoke(frame.method, id, frame.args or {}, frame.argn or 0))
      end)()
    end,
    [K.NEXT] = resume_iter(true),
    [K.STOP] = resume_iter(false),
  }

  start_reader(req_pipe, handlers, function()
    rsp_pipe:shutdown(function()
      rsp_pipe:close()
    end)
  end)

  vim.uv.run()
end

return M
