---@class lib.Queue<T>
---@field push fun(item: T)
---@field pop fun(): T?
---@field len fun(): integer

local M = {}

---@generic T
---@return lib.Queue<T>
M.new = function()
  local data, head, tail = {}, 1, 0

  local q = {}

  q.push = function(item)
    tail = tail + 1
    data[tail] = item
  end

  q.pop = function()
    if head > tail then
      return nil
    end
    local item = data[head]
    data[head] = nil
    head = head + 1
    return item
  end

  q.len = function()
    return tail - head + 1
  end

  return q
end

return M
