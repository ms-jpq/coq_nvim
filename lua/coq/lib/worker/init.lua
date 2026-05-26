local async = require "coq.lib.async"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local inflight = require "coq.lib.worker.inflight"
local lib = require "coq.lib"
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

local response = function(id, ok, ...)
  return {
    kind = Kind.YIELD,
    id = id,
    ok = ok,
    n_values = select("#", ...),
    values = { ... },
  }
end

local dump_cache = setmetatable({}, { __mode = "k" })

local dump = function(fn)
  local bytecode = dump_cache[fn]
  if not bytecode then
    bytecode = string.dump(fn)
    dump_cache[fn] = bytecode
  end
  return bytecode
end

local pack_call = function(fn, ...)
  return {
    fn_bytecode = dump(fn),
    args = { ... },
    n_args = select("#", ...),
  }
end

local M = {}

local requester = function(write)
  local STATE = { INITIAL = "initial", STREAMING = "streaming", DONE = "done" }
  local flights = inflight.new()
  local requester = {}

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
    local unwatch = lib.noop

    local cleanup = function()
      state = STATE.DONE
      unwatch()
      unwatch = lib.noop
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

  requester.request_oneshot = function(message)
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

  requester.request_stream = function(message)
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

  requester.resolve = function(frame)
    flights.resolve(frame.id, frame)
  end

  requester.drain = flights.drain

  return requester
end

local responder = function(write)
  local parked = inflight.new()
  local scheduled = vim.is_thread() and lib.noop or require("coq.lib.async.vim").scheduled

  -- A yield fn for the user's streaming code. Packs all args into one table so
  -- async.stream's single-value emit semantics preserve multi-value yields.
  -- Returns the puller's resume value (true on NEXT, false on STOP/cancel).
  -- Once the request handle is cancelled, future calls short-circuit to false
  -- without sending a YIELD frame -- matches the old yield_fn semantics so
  -- user code can branch on a `false` return for cleanup.
  local make_user_yield = function()
    return function(...)
      local h = runtime.current()
      if h.cancelled then
        return false
      end
      local n = select("#", ...)
      assert(n > 0, "yield: at least one value required")
      for i = 1, n do
        assert(select(i, ...) ~= nil, "yield: nil value at position " .. i)
      end
      return coroutine.yield { n = n, ... }
    end
  end

  local serve_oneshot = function(frame)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return write(response(frame.id, false, err or errs.UNKNOWN))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    write(response(frame.id, pcall(fn, unpack(args, 1, n_args))))
  end

  local serve_stream = function(frame, req_handle, defer)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return write(response(frame.id, false, err or errs.UNKNOWN))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0

    -- NEXT/STOP from the caller: STOP cancels, NEXT releases back-pressure.
    -- On cancel we close next_chan so any in-flight pull returns rather than
    -- parking forever.
    local next_chan = mpmc.new()
    local _, release = parked.reserve(function(rsp)
      if rsp.kind == Kind.STOP then
        req_handle.cancel()
      else
        next_chan.push(true)
      end
    end, frame.id)
    defer(release)
    req_handle.on_cancel(next_chan.close)

    local user_yield = make_user_yield()
    local stream_err
    local pull = runtime.stream(function()
      local ok, e = xpcall(function()
        fn(user_yield, unpack(args, 1, n_args))
      end, debug.traceback)
      if not ok then
        stream_err = e
      end
    end, req_handle)

    local packed = pull()
    while packed ~= nil do
      write { kind = Kind.YIELD, id = frame.id, n_values = packed.n, values = packed }
      local cont = next_chan.pull()
      if req_handle.cancelled or not cont then
        -- Resume the producer once more with `false` so the user fn's next
        -- yield call returns false (matches the old yield_fn cleanup signal).
        pull(false)
        break
      end
      packed = pull(true)
    end

    if stream_err then
      write(response(frame.id, false, stream_err))
    else
      write(response(frame.id, true))
    end
  end

  local responder = {}

  responder.serve = function(n, frame)
    local req_handle = handle.new(runtime.current())

    n.spawn(function(defer)
      defer(req_handle.cancel)
      runtime.bind(coroutine.running(), req_handle)
      scheduled()
      if frame.streaming then
        serve_stream(frame, req_handle, defer)
      else
        serve_oneshot(frame)
      end
    end)
  end

  responder.resolve = function(frame)
    parked.resolve(frame.id, frame)
  end

  return responder
end

local make_endpoint = function(duplex)
  local write = transport.writer(duplex.writer)
  local caller = requester(write)
  local callee = responder(write)

  local handlers = {
    [Kind.YIELD] = caller.resolve,
    [Kind.NEXT] = callee.resolve,
    [Kind.STOP] = callee.resolve,
  }

  return {
    request_oneshot = caller.request_oneshot,
    request_stream = caller.request_stream,
    drain = caller.drain,
    dispatch = function(n, frame)
      if frame.kind == Kind.REQUEST then
        callee.serve(n, frame)
        return
      end

      n.spawn(function()
        handlers[frame.kind](frame)
      end)
    end,
  }
end

if vim.is_thread() then
  M.run = function(req_fd, rsp_fd)
    local duplex = transport.open_duplex(req_fd, rsp_fd)

    local endpoint = make_endpoint(duplex)

    M.main = function(fn, ...)
      return endpoint.request_oneshot(pack_call(fn, ...))
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
end

M.spawn = function()
  local duplex, remote = transport.duplex_pair()
  local closed = false

  local endpoint = make_endpoint(duplex)

  transport.spawn_worker(function(...)
    require("coq.lib.worker").run(...)
  end, remote.read_fd, remote.write_fd)

  local n = nursery.new()

  local worker = {}

  worker.queue = function(fn, ...)
    if closed then
      error("worker closed", 2)
    end
    return endpoint.request_oneshot(pack_call(fn, ...))
  end

  worker.queue_stream = function(fn, ...)
    if closed then
      error("worker closed", 2)
    end
    local message = pack_call(fn, ...)
    message.streaming = true
    return endpoint.request_stream(message)
  end

  worker.close = function()
    if not closed then
      closed = true
      duplex.close()
    end
    n.join()
  end

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

  return worker
end

return M
