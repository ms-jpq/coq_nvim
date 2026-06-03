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
---@param pred fun(v: T): boolean
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.take_while = function(pred, iter)
  local done = false
  return function()
    if done then
      return nil
    end
    for v in iter do
      if not pred(v) then
        done = true
        return nil
      end
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
---@param ... lib.Iterator<T>
---@return lib.Iterator<T>
M.chain = function(...)
  local iters = { ... }
  local i = 1
  return function()
    while i <= #iters do
      local v = iters[i]()
      if v ~= nil then
        return v
      end
      i = i + 1
    end
    return nil
  end
end

return M
