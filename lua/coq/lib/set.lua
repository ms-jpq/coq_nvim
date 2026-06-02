---@alias lib.Set<T> table<T, true>

local M = {}

---@generic T
---@param items? T[]
---@return lib.Set<T>
M.new = function(items)
  local s = {}
  for _, v in pairs(items or {}) do
    s[v] = true
  end
  return s
end

return M
