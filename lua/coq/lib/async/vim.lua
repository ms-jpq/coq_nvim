local async = require "coq.lib.async"

local M = {}

M.scheduled = async.wrap(vim.schedule)
M.system = async.wrap(vim.system)
M.fn = {
  jobstart = async.wrap(function(cmd, opts, on_exit)
    opts = opts or {}
    opts.on_exit = on_exit
    vim.fn.jobstart(cmd, opts)
  end),
}
M.ui = {
  select = async.wrap(vim.ui.select),
}

return M
