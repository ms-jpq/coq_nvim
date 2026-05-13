local channel = require "coq.lib.worker.channel"
local errs = require "coq.lib.errs"
local proto = require "coq.lib.worker.proto"

local K = proto.KIND

local M = {}

M.new = function(req_write, inflight, send_request)
  return function(method, args, argn)
    local chan = channel.mpsc()
    local id, release = inflight.reserve(chan.push)
    send_request(id, method, args, argn)

    local done, first = false, true

    local it = {}
    it.close = function()
      if done then
        return
      end
      done = true

      req_write:write(proto.encode { kind = K.STOP, id = id })
      release()
    end

    local next = function()
      if done then
        return nil
      end

      if not first then
        req_write:write(proto.encode { kind = K.NEXT, id = id })
      end
      first = false

      local frame = chan.pull()
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
