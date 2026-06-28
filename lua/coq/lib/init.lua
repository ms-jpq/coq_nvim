local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"

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
---@param tbl table<K, V>
---@param mode? "k" | "v" | "kv"
---@return table<K, V>
M.weak = function(tbl, mode)
  return setmetatable(tbl, { __mode = mode or "k" })
end

---@return string
M.getcwd = function()
  local ok, cwd = pcall(vim.fn.getcwd)
  return ok and cwd or ""
end

---@param fn fun(defer: fun(cleanup: fun())): ...
---@return ...
M.scope = function(fn)
  local defers = {}

  local finish = function(ok, ...)
    local errors = {}
    if not ok then
      table.insert(errors, (...))
    end

    for i = #defers, 1, -1 do
      local d_ok, d_err = xpcall(defers[i], function(e)
        return cancel.is(e) and e or debug.traceback(e)
      end)
      if not d_ok then
        table.insert(errors, d_err)
      end
    end

    errs.check_raise(errors)
    return ...
  end

  return finish(pcall(fn, function(defer)
    table.insert(defers, defer)
  end))
end

return M
