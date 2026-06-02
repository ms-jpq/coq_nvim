local errs = require "coq.lib.errs"

---@class lib.Closable
---@field close fun()

---@alias lib.Iterator<T> fun(): T?

---@class lib.Iterable<T>
---@field iter fun(): lib.Iterator<T>

local M = {}

M.group = vim.api.nvim_create_augroup and vim.api.nvim_create_augroup("coq", { clear = true })

M.is_windows = vim.uv.os_uname().sysname == "Windows_NT"

---@param ... any
M.noop = function(...) end

---@param lo integer
---@param x integer
---@param hi integer
---@return integer
M.clamp = function(lo, x, hi)
  return math.max(lo, math.min(x, hi))
end

---@generic K, V
---@return table<K, V>
M.weak = function()
  return setmetatable({}, { __mode = "k" })
end

---@param fn fun(defer: fun(cleanup: fun())): ...
---@return ...
M.scope = function(fn)
  local defers = {}

  local finish = function(ok, ...)
    for i = #defers, 1, -1 do
      local d_ok, d_err = xpcall(defers[i], debug.traceback)
      if not d_ok then
        errs.report(d_err)
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
