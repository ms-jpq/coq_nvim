local errs = require "coq.lib.errs"
local proto = require "coq.lib.worker.proto"

local M = {}

local next_id = (function()
  local id = 0

  return function()
    id = id + 1
    return id
  end
end)()

local DEAD_FRAME = function(reason)
  return { kind = proto.KIND.RESPONSE, ok = false, n = 1, values = { reason } }
end

M.new = function()
  local mapping = {}

  return {
    reserve = function(cb)
      local id = next_id()
      mapping[id] = function(frame)
        mapping[id] = nil
        if frame.ok then
          cb(nil, unpack(frame.values, 1, frame.n))
        else
          cb(frame.values[1] or errs.UNKNOWN)
        end
      end
      return id
    end,
    reserve_raw = function(cb)
      local id = next_id()
      mapping[id] = cb
      return id, function()
        mapping[id] = nil
      end
    end,
    resolve = function(frame)
      local handler = mapping[frame.id]
      if handler then
        handler(frame)
      end
    end,
    drain = function(reason)
      for _, handler in pairs(mapping) do
        handler(DEAD_FRAME(reason))
      end
      mapping = {}
    end,
  }
end

return M
