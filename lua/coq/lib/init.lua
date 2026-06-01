---@class lib.Closable
---@field close fun()

---@alias lib.Iterator<T> fun(): T?

---@class lib.Iterable<T>
---@field iter fun(): lib.Iterator<T>

---@class lib.ClosableIter<T>: lib.Closable
---@overload fun(): T?

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

---@type lib.ClosableIter<any>
M.dead_iter = setmetatable({ close = M.noop }, {
  __call = function()
    return nil
  end,
})

---@param err any
M.report = function(err)
  local e = tostring(err)
  vim.schedule(function()
    vim.notify(e, vim.log.levels.ERROR)
  end)
end

---@param s string
---@return fun(): string?
M.splitlines = function(s)
  local normalized = string.gsub(s, "\r\n?", "\n")
  return vim.gsplit(normalized, "\n", { plain = true })
end

---@param fn fun(defer: fun(cleanup: fun())): ...any
---@return ...any
M.scope = function(fn)
  local defers = {}

  local finish = function(ok, ...)
    for i = #defers, 1, -1 do
      local d_ok, d_err = xpcall(defers[i], debug.traceback)
      if not d_ok then
        M.report(d_err)
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
