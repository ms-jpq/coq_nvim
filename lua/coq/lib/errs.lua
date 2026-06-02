local cancel = require "coq.lib.async.cancel"

---@class lib.ErrorGroup<T>
---@field errs T[]

local M = {}

local thread_sink = nil

---@param fn fun(message: string)
M.set_thread_sink = function(fn)
  thread_sink = fn
end

---@param err any
M.report = function(err)
  if vim.is_thread() then
    if thread_sink then
      pcall(thread_sink, tostring(err))
    end
  else
    vim.schedule(function()
      vim.notify(err, vim.log.levels.ERROR)
    end)
  end
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

  if #es == 1 then
    error(es[1], 0)
  end

  for _, e in ipairs(es) do
    if not cancel.is(e) then
      error(M.group(es), 0)
    end
  end
  error(es[1], 0)
end

return M
