local M = {}

M.group = [[coq]]

M.noop = function(...) end

M.scope = function(fn)
  local defers = {}
  local rets = { xpcall(fn, debug.traceback, function(defer)
    table.insert(defers, defer)
  end) }

  for i = #defers, 1, -1 do
    local ok, err = xpcall(defers[i], debug.traceback)
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
