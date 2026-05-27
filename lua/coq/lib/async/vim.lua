local async = require "coq.lib.async"

local M = {}

---@type fun()
M.scheduled = async.awaitify(vim.schedule)

---@type fun(cmd: string|string[], opts?: vim.SystemOpts): vim.SystemCompleted
M.system = async.awaitify(vim.system)

M.fn = {
  ---@type fun(cmd: string|string[], opts?: table): integer
  jobstart = async.awaitify(function(cmd, opts, on_exit)
    opts = opts or {}
    opts.on_exit = on_exit
    vim.fn.jobstart(cmd, opts)
  end),
}

M.ui = {
  ---@generic T
  ---@type fun(items: T[], opts: table): T?, integer?
  select = async.awaitify(vim.ui.select),
}

return M
