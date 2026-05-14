local M = {}

local next_id = (function()
  local id = 0

  return function()
    id = id + 1
    return id
  end
end)()

local DEAD_FRAME = function(reason)
  return { kind = "response", ok = false, n = 1, values = { reason } }
end

M.new = function()
  local mapping = {}

  return {
    reserve = function(cb)
      local id = next_id()
      mapping[id] = cb
      return id, function()
        mapping[id] = nil
      end
    end,
    resolve = function(frame)
      local cb = mapping[frame.id]
      if cb then
        cb(frame)
      end
    end,
    drain = function(reason)
      for _, cb in pairs(mapping) do
        cb(DEAD_FRAME(reason))
      end
      mapping = {}
    end,
  }
end

return M
