local async = require "coq.lib.async"

local M = {}

---@generic T
---@param every integer
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.cooperative = function(every, iter)
  local pulled = 0
  return function()
    for v in iter do
      pulled = pulled + 1
      if pulled >= every then
        pulled = 0
        async.sleep(0)
      end
      return v
    end
    return nil
  end
end

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
    for v in iter do
      n = n + 1
      return v
    end
    return nil
  end
end

---@generic T
---@param sep T
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.intersperse = function(sep, iter)
  local idx, peek = 0, iter()
  return function()
    idx = idx + 1
    if peek == nil then
      return nil
    end
    if idx % 2 == 0 then
      return sep
    end
    local v = peek
    peek = iter()
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
