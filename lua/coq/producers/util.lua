local M = {}

---@generic T
---@param iter fun(): T?
---@param key fun(item: T): any
---@return fun(): T?
M.dedup = function(iter, key)
  local seen = {}
  return function()
    for item in iter do
      local k = key(item)
      if not seen[k] then
        seen[k] = true
        return item
      end
    end
    return nil
  end
end

return M
