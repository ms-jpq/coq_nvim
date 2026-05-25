local async = require "coq.lib.async"
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
    local unwatch = function() end

    local cleanup = function()
      state = STATE.DONE
      unwatch()
      unwatch = function() end
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
  local scheduled = vim.is_thread() and function() end or require("coq.lib.async.vim").scheduled

  local invoke = function(frame, yield)
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      return response(frame.id, false, err or errs.UNKNOWN)
    end
    local args, n_args = frame.args or {}, frame.n_args or 0
    if frame.streaming then
      return response(frame.id, pcall(fn, yield, unpack(args, 1, n_args)))
    end
    return response(frame.id, pcall(fn, unpack(args, 1, n_args)))
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

  local responder = {}

  responder.serve = function(n, frame)
    local req_handle = handle.new(runtime.current())
    local yield_fn = make_yield(frame.id, req_handle)

    n.spawn(function(defer)
      defer(req_handle.cancel)
      runtime.bind(coroutine.running(), req_handle)
      scheduled()
      write(invoke(frame, yield_fn))
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
