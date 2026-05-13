-- Worker-side dispatch loop. Called by the (string.dump'd) thunk in init.lua
-- after package.path has been wired up.

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config"
local errs = require "coq.lib.errs"
local inflight = require "coq.lib.worker.inflight"
local proto = require "coq.lib.worker.proto"

local K = proto.KIND

return function(req_fd, rsp_fd, raw)
  local req_pipe, rsp_pipe = vim.uv.new_pipe(), vim.uv.new_pipe()
  req_pipe:open(req_fd)
  rsp_pipe:open(rsp_fd)

  local state, methods = config.decode(raw)
  local iter_resumers = {}
  local tracker = inflight.new()

  local send = proto.sender(rsp_pipe)
  local respond = proto.responder(send, K.RESPONSE)

  local worker = require "coq.lib.worker"
  worker.main = function(fn, ...)
    local argn = select("#", ...)
    local args = { ... }
    local id, release
    local resolve, await = async.future()

    id, release = tracker.reserve(function(frame)
      release()
      if frame.ok then
        resolve(nil, unpack(frame.values, 1, frame.n))
      else
        resolve(frame.values[1] or errs.UNKNOWN)
      end
    end)

    send {
      kind = K.REQUEST,
      id = id,
      fn_dump = string.dump(fn),
      args = args,
      argn = argn,
    }
    return proto.unwrap(await())
  end

  local make_yield = function(id)
    return function(...)
      local argn = select("#", ...)
      local args = { ... }
      send { kind = K.YIELD, id = id, n = argn, values = args }
      local resolve, await = async.future()
      iter_resumers[id] = resolve
      return await()
    end
  end

  local invoke = function(name, id, args, argn)
    local m = methods[name]
    if not m then
      return false, 1, { "unknown method: " .. tostring(name) }
    end
    if m.mode == proto.MODE.STREAM then
      local ok, err = pcall(m.fn, make_yield(id), state, unpack(args, 1, argn))
      iter_resumers[id] = nil
      if ok then
        return true, 0, {}
      end
      return false, 1, { err }
    end
    return proto.pack(pcall(m.fn, state, unpack(args, 1, argn)))
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
      async.run(async.ROOT, function()
        respond(id, invoke(frame.method, id, frame.args or {}, frame.argn or 0))
      end)
    end,
    [K.NEXT] = resume_iter(true),
    [K.STOP] = resume_iter(false),
  }

  proto.start_reader(req_pipe, handlers, function()
    rsp_pipe:shutdown(function()
      rsp_pipe:close()
    end)
  end)

  vim.uv.run()
end
