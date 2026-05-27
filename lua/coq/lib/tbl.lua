local M = {}

---@generic T
---@param t T[]
M.shuffle = function(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

return M
