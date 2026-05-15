local M = {}

local next_id = (function()
  local id = 0

  return function()
    id = id + 1
    return id
  end
end)()

M.new = function()
  local mapping = {}
  local parker = {}

  parker.reserve = function(cb, id)
    id = id or next_id()
    mapping[id] = cb
    return id, function()
      mapping[id] = nil
    end
  end

  parker.resolve = function(id, message)
    local cb = mapping[id]
    if cb then
      cb(message)
    end
  end

  parker.drain = function(message)
    local acc = mapping
    mapping = {}
    for _, cb in pairs(acc) do
      cb(message)
    end
  end

  return parker
end

return M
