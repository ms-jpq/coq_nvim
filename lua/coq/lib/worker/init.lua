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

---@type table<function, string>
local dump_cache = setmetatable({}, { __mode = "k" })

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
local pack_request = function(fn, ...)
  return {
    fn_bytecode = dump(fn),
    args = { ... },
    n_args = select("#", ...),
  }
end

---@param id integer?
---@param ok boolean
---@param ... any
---@return table
local make_response = function(id, ok, ...)
  return {
    kind = Kind.YIELD,
    id = id,
    ok = ok,
    n_values = select("#", ...),
    values = { ... },
  }
end

---@class worker.Session: lib.Closable
---@field next fun(): table?

---@param parked worker.Inflight
---@param write fun(body: table)
---@param message table
---@return worker.Session
local open = function(parked, write, message)
  local chan = mpmc.new(1)
  local id, release = parked.reserve(chan.push)

  message.kind, message.id = Kind.REQUEST, id
  local ok, err = xpcall(write, debug.traceback, message)
  if not ok then
    release()
    chan.close()
    error(err, 0)
  end

  local closed = false
  local unwatch = lib.noop

  local cleanup = function()
    if closed then
      return
    end
    closed = true
    unwatch()
    release()
    chan.close()
  end

  local frames = runtime.wrap(function()
    while true do
      local frame = chan.pull()
      if frame == nil then
        write { kind = Kind.STOP, id = id }
        return
      end
      coroutine.yield(frame)
      if frame.ok ~= nil then
        return
      end
      write { kind = Kind.NEXT, id = id }
    end
  end)

  local session = {}

  session.next = function()
    if closed then
      return nil
    end
    local frame = frames()
    if frame == nil or frame.ok ~= nil then
      cleanup()
    end
    return frame
  end

  session.close = function()
    if closed then
      return
    end
    write { kind = Kind.STOP, id = id }
    cleanup()
  end

  unwatch = runtime.current().on_cancel(session.close)

  ---@cast session worker.Session
  return session
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

  local interpret_frame = function(frame, level)
    if frame == nil then
      return
    end
    if frame.ok == false then
      error(frame.values[1] or errs.UNKNOWN, level + 1)
    end
    return unpack(frame.values, 1, frame.n_values)
  end

  local requester = { drain = parked.drain }

  requester.request_oneshot = function(message)
    local session = open(parked, write, message)
    return interpret_frame(session.next(), 3)
  end

  requester.request_stream = function(message)
    local session = open(parked, write, message)
    local next = function()
      return interpret_frame(session.next(), 2)
    end
    return setmetatable({ close = session.close }, { __call = next })
  end

  requester.resolve = function(frame)
    parked.resolve(frame.id, frame)
  end

  ---@cast requester worker.Requester
  return requester
end

---@class worker.Responder
---@field serve fun(n: async.Nursery, frame: table)
---@field resolve fun(frame: table)

---@param write fun(body: table)
---@return worker.Responder
local make_responder = function(write)
  local parked = inflight.new()

  local load_func = function(frame)
    local args, n_args = frame.args or {}, frame.n_args or 0
    local fn, err = load(frame.fn_bytecode)
    if not fn then
      write(make_response(frame.id, false, err or errs.UNKNOWN))
      return nil, args, n_args
    end
    return fn, args, n_args
  end

  local dispatch = function(frame, req_handle, next_chan)
    local fn, args, n_args = load_func(frame)
    if not fn then
      return
    end

    if not next_chan then
      write(make_response(frame.id, pcall(fn, unpack(args, 1, n_args))))
      return
    end

    local stream = runtime.wrap(fn, req_handle)

    local consume = function()
      local item = stream(unpack(args, 1, n_args))
      while item ~= nil do
        write { kind = Kind.YIELD, id = frame.id, n_values = 1, values = { item } }
        if req_handle.cancelled or not next_chan.pull() then
          for _ in stream do
            lib.noop()
          end
          break
        end
        item = stream(true)
      end
    end

    write(make_response(frame.id, pcall(consume)))
  end

  local responder = {}
  local scheduled = vim.is_thread() and lib.noop or require("coq.lib.async.vim").scheduled

  responder.serve = function(n, frame)
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
      dispatch(frame, req_handle, next_chan)
    end)
  end

  responder.resolve = function(frame)
    parked.resolve(frame.id, frame)
  end

  ---@cast responder worker.Responder
  return responder
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

  local serve = function(n, dead_message)
    for frame in transport.reader(duplex.reader) do
      local kind = frame.kind
      if kind == Kind.REQUEST then
        responder.serve(n, frame)
      elseif kind == Kind.YIELD then
        n.spawn(function()
          requester.resolve(frame)
        end)
      else
        n.spawn(function()
          responder.resolve(frame)
        end)
      end
    end
    requester.drain(make_response(nil, false, dead_message))
  end

  return {
    request_oneshot = requester.request_oneshot,
    request_stream = requester.request_stream,
    serve = serve,
  }
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
      return endpoint.request_oneshot(pack_request(fn, ...))
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
    return endpoint.request_oneshot(pack_request(fn, ...))
  end

  worker.queue_stream = function(fn, ...)
    if closed then
      error("worker closed", 2)
    end
    local message = pack_request(fn, ...)
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
    endpoint.serve(n, "worker died")
  end)

  ---@cast worker worker.Worker
  return worker
end

return M
