local M = {}

M.new = function()
  local data, head, tail = {}, 1, 0

  local q = {}

  q.push = function(row)
    tail = tail + 1
    data[tail] = row
  end

  q.pop = function()
    if head > tail then
      return nil
    end
    local row = data[head]
    data[head] = nil
    head = head + 1
    return row
  end

  q.len = function()
    return tail - head + 1
  end

  return q
end

return M
