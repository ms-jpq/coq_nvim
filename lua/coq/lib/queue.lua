local M = {}

M.new = function()
  local push, pop = {}, {}
  local q = {}

  q.push = function(val)
    table.insert(push, val)
  end

  q.pop = function()
    if #pop == 0 then
      while #push ~= 0 do
        table.insert(pop, table.remove(push))
      end
    end
    return table.remove(pop)
  end

  return setmetatable(q, {
    __len = function()
      return #push + #pop
    end,
  })
end

return M
