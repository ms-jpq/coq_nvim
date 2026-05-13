local async = require "coq.lib.async"
local errs = require "coq.lib.errs"
local proto = require "coq.lib.worker.proto"

local K = proto.KIND

local M = {}

M.wrap = function(fn)
  return { streaming = true, fn = fn }
end

M.is = function(decl)
  return type(decl) == "table" and decl.streaming == true
end

M.new = function(send, inflight, send_request)
  return function(method, args, argn)
    local resolve, await = async.future()
    local id, release = inflight.reserve(function(frame)
      resolve(frame)
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
        resolve, await = async.future()
        send { kind = K.NEXT, id = id }
      end
      first = false

      local frame = await()
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

return M
