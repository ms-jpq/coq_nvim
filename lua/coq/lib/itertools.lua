local M = {}

---@generic T
---@param max integer
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.take = function(max, iter)
  local n = 0
  return function()
    if n >= max then
      return nil
    end
    local v = iter()
    if v == nil then
      return nil
    end
    n = n + 1
    return v
  end
end

---@generic T
---@param key_fn fun(item: T): any
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.uniq_by = function(key_fn, iter)
  local seen = {}
  return function()
    for v in iter do
      local key = key_fn(v)
      if key == nil then
        return v
      end
      if not seen[key] then
        seen[key] = true
        return v
      end
    end
    return nil
  end
end

return M
