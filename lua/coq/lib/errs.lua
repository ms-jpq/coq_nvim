local cancel = require "coq.lib.async.cancel"

---@class lib.ErrorGroup<T>
---@field errs T[]

local M = {}

local thread_sink = function() end

---@param fn fun(message: string)
M.set_thread_sink = function(fn)
  thread_sink = fn
end

---@type fun(err: any)
M.report = vim.is_thread() and function(err)
  pcall(thread_sink, tostring(err))
end or function(err)
  vim.schedule(function()
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end)
end

---@generic F: fun(...)
---@param fn F
---@return F
M.with_reporting = function(fn)
  return function(...)
    cancel.xpcall(fn, M.report, ...)
  end
end

---@generic T
---@param es T[]
---@return lib.ErrorGroup<T>
M.group = function(es)
  return setmetatable({ errs = es }, {
    __tostring = function(self)
      local header = string.format("error group (%d errors):", #self.errs)
      local body = vim
        .iter(self.errs)
        :enumerate()
        :map(function(i, e)
          return string.format("  [%d] %s", i, tostring(e))
        end)
        :totable()
      return header .. "\n" .. table.concat(body, "\n")
    end,
  })
end

---@generic T
---@param es T[]
M.raise = function(es)
  if #es == 0 then
    return
  end

  local non_cancel = vim.tbl_filter(function(e)
    return not cancel.is(e)
  end, es)

  if #non_cancel == 0 then
    error(es[1], 0)
  elseif #non_cancel == 1 then
    error(non_cancel[1], 0)
  else
    error(M.group(non_cancel), 0)
  end
end

return M
