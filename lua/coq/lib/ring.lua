---@class lib.Ring<T>
---@field len fun(): integer
---@field push fun(item: T)
---@field items fun(): T[]

local M = {}

---@generic T
---@param cap integer
---@return lib.Ring<T>
M.new = function(cap)
  local data, write_idx = {}, 0

  local r = {}

  r.len = function()
    return #data
  end

  r.push = function(item)
    write_idx = write_idx % cap + 1
    data[write_idx] = item
  end

  r.items = function()
    local out = {}
    for i, v in ipairs(data) do
      out[i] = v
    end
    return out
  end

  return r
end

return M
