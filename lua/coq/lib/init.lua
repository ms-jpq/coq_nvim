local M = {}

M.group = [[coq]]

M.scope = function(fn)
  local defers = {}
  local rets = { pcall(fn, function(defer)
    table.insert(defers, defer)
  end) }

  for defer in vim.iter(defers):rev() do
    local ok, err = pcall(defer)
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end

  if rets[1] then
    return unpack(rets, 2)
  else
    error(rets[2], 0)
  end
end

return M
