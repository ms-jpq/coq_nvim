local M = {}

M.group = [[coq]]

M.noop = function(...) end

M.scope = function(fn)
  local defers = {}

  local finish = function(ok, ...)
    for i = #defers, 1, -1 do
      local d_ok, d_err = xpcall(defers[i], debug.traceback)
      if not d_ok then
        vim.notify(d_err, vim.log.levels.ERROR)
      end
    end

    if ok then
      return ...
    end
    error((...), 0)
  end

  return finish(xpcall(fn, debug.traceback, function(defer)
    table.insert(defers, defer)
  end))
end

return M
