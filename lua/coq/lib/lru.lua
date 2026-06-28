---@alias lib.LRU table

local INNER = {}

local M = {}

---@param capacity integer
---@return lib.LRU
M.new = function(capacity)
  assert(capacity > 0, "lru: capacity must be > 0")
  local values = {}
  local prev, next = {}, {}
  local head, tail = nil, nil
  local size = 0

  local detach = function(key)
    local p, n = prev[key], next[key]
    if p then
      next[p] = n
    else
      head = n
    end
    if n then
      prev[n] = p
    else
      tail = p
    end
    prev[key], next[key] = nil, nil
  end

  local attach_head = function(key)
    next[key] = head
    if head then
      prev[head] = key
    end
    head = key
    if not tail then
      tail = key
    end
  end

  return setmetatable({}, {
    __index = function(_, key)
      if key == INNER then
        return values
      end
      local v = values[key]
      if v == nil then
        return nil
      end
      detach(key)
      attach_head(key)
      return v
    end,
    __newindex = function(_, key, value)
      if value == nil then
        if values[key] ~= nil then
          values[key] = nil
          detach(key)
          size = size - 1
        end
        return
      end
      if values[key] ~= nil then
        detach(key)
      else
        if size >= capacity and tail then
          local evict = tail
          values[evict] = nil
          detach(evict)
          size = size - 1
        end
        size = size + 1
      end
      values[key] = value
      attach_head(key)
    end,
  })
end

---@param cache lib.LRU
M.pairs = function(cache)
  return pairs(cache[INNER])
end

return M
