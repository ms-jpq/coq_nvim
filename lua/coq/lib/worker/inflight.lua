---@class worker.Inflight
---@field reserve fun(cb: fun(message: any), id?: integer): integer, fun()
---@field resolve fun(id: integer, message: any)
---@field drain fun(message: any)

local M = {}

---@return worker.Inflight
M.new = function()
  local mapping = {}
  local seq = 0
  local parker = {}

  parker.reserve = function(cb, id)
    if id == nil then
      seq = seq + 1
      id = seq
    end
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

  ---@cast parker worker.Inflight
  return parker
end

return M
