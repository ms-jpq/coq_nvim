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

local response = function(id, ok, ...)
  return {
    kind = Kind.YIELD,
    id = id,
    ok = ok,
    n_values = select("#", ...),
    values = { ... },
  }
end

local requester = function(write)
  local flights = inflight.new()
  local requester = {}

  local open = function(message)
    local chan = mpmc.new(1)
    local id, release = flights.reserve(chan.push)

    message.kind, message.id = Kind.REQUEST, id
    local ok, err = xpcall(write, debug.traceback, message)
    if not ok then
      release()
      chan.close()
      error(err, 0)
    end

    local done = false
    local started = false
    local session = {}
    local unwatch = lib.noop

    local cleanup = function()
      done = true
      unwatch()
      unwatch = lib.noop
      release()
      chan.close()
    end

    session.next = function()
      if done then
        return nil
      end

      if started then
        write { kind = Kind.NEXT, id = id }
      end

      local frame = chan.pull()
      if frame == nil then
        write { kind = Kind.STOP, id = id }
        cleanup()
        return nil
      end
      if frame.ok ~= nil then
        cleanup()
        return frame
      end
      started = true
      return frame
    end

    session.close = function()
      if done then
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

  local serve_oneshot = function(frame)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return write(response(frame.id, false, err or errs.UNKNOWN))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    write(response(frame.id, pcall(fn, unpack(args, 1, n_args))))
  end

  local serve_stream = function(frame, req_handle, next_chan)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return write(response(frame.id, false, err or errs.UNKNOWN))
    end
    local args, n_args = frame.args or {}, frame.n_args or 0

    -- The user fn emits via bare `coroutine.yield(row)`; runtime.stream
    -- captures each emit and the puller forwards it to the wire. NEXT releases
    -- back-pressure; STOP cancels req_handle (closing next_chan). The yield's
    -- return value is whatever the puller passes on resume -- true on NEXT,
    -- false on cancel -- letting user code branch for cleanup.
    local stream_err
    local stream = runtime.stream(function()
      local ok, e = pcall(fn, unpack(args, 1, n_args))
      if not ok then
        stream_err = e
      end
    end, req_handle)

    -- Forward rows to the wire, respecting NEXT/STOP backpressure. On stop or
    -- cancel, drain remaining yields with `false` so user fn sees false on each
    -- and can clean up; emitted values are discarded.
    local pump = function()
      local row = stream()
      while row ~= nil do
        write { kind = Kind.YIELD, id = frame.id, n_values = 1, values = { row } }
        local cont = next_chan.pull()
        if req_handle.cancelled or not cont then
          while stream(false) ~= nil do
          end
          return
        end
        row = stream(true)
      end
    end
    pump()

    if stream_err then
      write(response(frame.id, false, stream_err))
    else
      write(response(frame.id, true))
    end
  end

  local responder = {}

  responder.serve = function(n, frame)
    -- Reserve the NEXT/STOP parker SYNCHRONOUSLY so STOP frames arriving while
    -- the spawn is queued don't get dropped. Oneshot still needs the parker so
    -- a STOP from the caller (e.g., session.close on cancel) cancels the work
    -- instead of letting it run to completion.
    local req_handle = handle.new(runtime.current())
    local next_chan = frame.streaming and mpmc.new() or nil

    if next_chan then
      local _ = req_handle.on_cancel(next_chan.close)
    end

    local _, release = parked.reserve(function(rsp)
      if rsp.kind == Kind.STOP then
        req_handle.cancel()
      elseif next_chan then
        next_chan.push(true)
      end
    end, frame.id)

    n.spawn(function(defer)
      defer(req_handle.cancel)
      defer(release)
      runtime.bind(coroutine.running(), req_handle)
      scheduled()
      if next_chan then
        serve_stream(frame, req_handle, next_chan)
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

local M = {}

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
