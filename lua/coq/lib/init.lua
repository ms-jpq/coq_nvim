local M = {}

M.group = [[coq]]

---@param ... any
M.noop = function(...) end

---@param err any
M.report = function(err)
  local notify = function()
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end

  if vim.is_thread() then
    vim.schedule(notify)
  else
    notify()
  end
end

---@generic T
---@param fn fun(defer: fun(cleanup: fun())): T
---@return T
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

  return finish(pcall(fn, function(defer)
    table.insert(defers, defer)
  end))
end

return M
