local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local inflight = require "coq.lib.worker.inflight"
local lib = require "coq.lib"
local mpmc = require "coq.lib.channels.mpmc"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"
local transport = require "coq.lib.worker.frame_transport"
local util = require "coq.lib.channels.util"

local Kind = {
  RESUME = "resume",
  YIELD = "yield",
  STOP = "stop",
}

local DONE = {}

local raise_if_cancelled = function()
  if runtime.current().cancelled then
    error(cancel.new(), 0)
  end
end

---@type table<function, string>
local dump_cache = lib.weak()

---@param fn function
---@return string
local dump = function(fn)
  local bytecode = dump_cache[fn]
  if not bytecode then
    bytecode = string.dump(fn)
    dump_cache[fn] = bytecode
  end
  return bytecode
end

---@param fn function
---@param ... any
---@return table
local build_request = function(fn, ...)
  return {
    fn_bytecode = dump(fn),
    args = { ... },
    n_args = select("#", ...),
  }
end

---@param id integer?
---@param status boolean?
---@param ... any
---@return table
local build_response = function(id, status, ...)
  return {
    kind = Kind.YIELD,
    id = id,
    status = status,
    n_values = select("#", ...),
    values = { ... },
  }
end

---@class worker.Call: lib.Closable
---@field next fun(): table?

---@param parked worker.Inflight
---@param write fun(body: table)
---@param message table
---@return worker.Call
local open = function(parked, write, message)
  local chan = mpmc.new(1)
  local id, release = parked.reserve(chan.push)

  local primed = true
  local unwatch = lib.noop
  local state = util.closable(function()
    unwatch()
    release()
    chan.close()
  end)

  message.kind, message.id = Kind.RESUME, id
  local ok, err = xpcall(write, debug.traceback, message)
  if not ok then
    state.close()
    error(err, 0)
  end

  local call = {}

  call.close = function()
    if state.closed then
      return
    end
    write { kind = Kind.STOP, id = id }
    state.close()
  end

  unwatch = runtime.current().on_cancel(call.close)

  call.next = function()
    local frame = nil
    if not state.closed then
      if not primed then
        write { kind = Kind.RESUME, id = id }
      end
      primed = false
      frame = chan.pull()
      if frame == nil or frame.status ~= nil then
        state.close()
      end
    end

    raise_if_cancelled()
    return frame
  end

  ---@cast call worker.Call
  return call
end

---@param frame { status: boolean?, values: any[], n_values: integer }?
---@param level integer
---@return any ...
local interpret_frame = function(frame, level)
  if frame == nil then
    return
  end
  if frame.status == false then
    error(frame.values[1], level + 1)
  end
  return unpack(frame.values, 1, frame.n_values)
end

---@class worker.Requester
---@field drain fun(message: any)
---@field request_oneshot fun(message: table): any ...
---@field request_stream fun(message: table): worker.WorkerStream
---@field resolve fun(frame: table)

---@param write fun(body: table)
---@return worker.Requester
local make_requester = function(write)
  local parked = inflight.new()

  local requester = { drain = parked.drain }

  requester.request_oneshot = function(message)
    local call = open(parked, write, message)
    return interpret_frame(call.next(), 3)
  end

  requester.request_stream = function(message)
    local call = open(parked, write, message)
    local next = function()
      return interpret_frame(call.next(), 2)
    end
    return setmetatable({ close = call.close }, { __call = next })
  end

  requester.resolve = function(frame)
    parked.resolve(frame.id, frame)
  end

  ---@cast requester worker.Requester
  return requester
end

local scheduled = vim.is_thread() and lib.noop or atools.scheduled

---@class worker.Responder
---@field serve fun(n: async.Nursery, frame: table)

---@param write fun(body: table)
---@return worker.Responder
local make_responder = function(write)
  local dispatch = function(req_handle, chan, frame)
    local args, n_args = frame.args or {}, frame.n_args or 0

    local iter = async.wrap(function(...)
      local fn = assert(load(frame.fn_bytecode))
      return coroutine.yield(DONE, build_response(frame.id, pcall(fn, ...)))
    end)

    local resume = function(...)
      local packed = util.pack(iter(...))
      local done = packed[1] == DONE
      return done, done and packed[2] or packed
    end

    local pump = function()
      local done, packed = resume(unpack(args, 1, n_args))
      while not done do
        write(build_response(frame.id, nil, util.unpack(packed)))
        local more = not req_handle.cancelled and chan.pull()
        if not more then
          return build_response(frame.id, true)
        end
        done, packed = resume(true)
      end
      return packed
    end

    local ok, terminal = pcall(pump)
    local drained, err = pcall(function()
      for _ in iter do
        lib.noop()
      end
    end)
    if not drained and not cancel.is(err) then
      errs.report(err)
    end

    if not ok and cancel.is(terminal) then
      ok, terminal = true, build_response(frame.id, true)
    end

    write(ok and terminal or build_response(frame.id, false, terminal))
  end

  local parked = inflight.new()

  local serve = function(n, frame)
    if parked.has(frame.id) then
      n.spawn(errs.with_reporting(function()
        parked.resolve(frame.id, frame)
      end))
      return
    end
    if frame.kind ~= Kind.RESUME then
      return
    end

    local req_handle = handle.new(runtime.current())
    local chan = mpmc.new(1)
    local _ = req_handle.on_cancel(chan.close)

    local _, release = parked.reserve(function(rsp)
      if rsp.kind == Kind.STOP then
        req_handle.cancel()
      else
        chan.push(true)
      end
    end, frame.id)

    n.spawn(errs.with_reporting(function(defer)
      defer(req_handle.cancel)
      defer(release)
      runtime.bind(coroutine.running(), req_handle)
      scheduled()
      dispatch(req_handle, chan, frame)
    end))
  end

  return { serve = serve }
end

---@class worker.Endpoint
---@field request_oneshot fun(message: table): any ...
---@field request_stream fun(message: table): worker.WorkerStream
---@field serve fun(n: async.Nursery, dead_message: string)

---@param duplex worker.Duplex
---@return worker.Endpoint
local make_endpoint = function(duplex)
  local write = transport.writer(duplex.writer)
  local requester = make_requester(write)
  local responder = make_responder(write)

  local endpoint = { request_oneshot = requester.request_oneshot, request_stream = requester.request_stream }

  endpoint.serve = function(n, dead_message)
    for frame in transport.reader(duplex.reader) do
      if frame.kind == Kind.YIELD then
        n.spawn(errs.with_reporting(function()
          requester.resolve(frame)
        end))
      else
        responder.serve(n, frame)
      end
    end
    requester.drain(build_response(nil, false, dead_message))
  end

  ---@cast endpoint worker.Endpoint
  return endpoint
end

---@class worker.WorkerStream: lib.Closable
---@overload fun(): any ...

---@class worker.Worker: lib.Closable
---@field queue fun(fn: function, ...: any): any ...
---@field queue_stream fun(fn: function, ...: any): worker.WorkerStream

local M = {}

if vim.is_thread() then
  ---@param req_fd integer
  ---@param rsp_fd integer
  M.run = function(req_fd, rsp_fd)
    local duplex = transport.open_duplex(req_fd, rsp_fd)

    local endpoint = make_endpoint(duplex)

    M.main = function(fn, ...)
      return endpoint.request_oneshot(build_request(fn, ...))
    end

    M.main_stream = function(fn, ...)
      return endpoint.request_stream(build_request(fn, ...))
    end

    async.entry(function()
      async.scope(function(n, defer)
        defer(duplex.close)
        endpoint.serve(n, "host died")
      end)
    end)()

    vim.uv.run()
  end
end

---@return worker.Worker
M.spawn = function()
  local duplex, remote = transport.duplex_pair()
  local state = util.closable(duplex.close)

  local endpoint = make_endpoint(duplex)

  transport.spawn_worker(function(...)
    require("coq.lib.worker").run(...)
  end, remote.read_fd, remote.write_fd)

  local n = nursery.new()

  local worker = {}

  worker.queue = function(fn, ...)
    if state.closed then
      error("worker closed", 2)
    end
    return endpoint.request_oneshot(build_request(fn, ...))
  end

  worker.queue_stream = function(fn, ...)
    if state.closed then
      error("worker closed", 2)
    end
    return endpoint.request_stream(build_request(fn, ...))
  end

  worker.close = function()
    state.close()
    n.join()
  end

  n.spawn(errs.with_reporting(function()
    endpoint.serve(n, "worker died")
  end))

  ---@cast worker worker.Worker
  return worker
end

return M
