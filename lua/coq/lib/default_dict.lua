---@class lib.DefaultDict<K, V>: { [K]: V }

local M = {}

---@generic K, V
---@param factory fun(): V
---@return lib.DefaultDict<K, V>
M.new = function(factory)
  return setmetatable({}, {
    __index = function(t, k)
      local v = factory()
      rawset(t, k, v)
      return v
    end,
  })
end

return M
