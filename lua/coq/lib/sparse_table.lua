local M = {}

M.new = function()
  local map, count, head = {}, 0, 1

  local sparse = {}

  sparse.push = function(value)
    count = count + 1
    local key = count
    map[key] = value
    return key
  end

  sparse.remove = function(key)
    map[key] = nil
  end

  sparse.shift = function()
    while head <= count do
      local v = map[head]
      map[head] = nil
      head = head + 1
      if v ~= nil then
        return v
      end
    end
  end

  sparse.iter = function(rev)
    local k, stop, step
    if rev then
      k, stop, step = count + 1, 1, -1
    else
      k, stop, step = 0, count, 1
    end
    return function()
      while (step > 0 and k < stop) or (step < 0 and k > stop) do
        k = k + step
        local v = map[k]
        if v ~= nil then
          return k, v
        end
      end
    end
  end

  return sparse
end

return M
