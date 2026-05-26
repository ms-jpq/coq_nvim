local async = require "coq.lib.async"

local M = {}

M.scheduled = async.awaitify(vim.schedule)
M.system = async.awaitify(vim.system)
M.fn = {
  jobstart = async.awaitify(function(cmd, opts, on_exit)
    opts = opts or {}
    opts.on_exit = on_exit
    vim.fn.jobstart(cmd, opts)
  end),
}
M.ui = {
  select = async.awaitify(vim.ui.select),
}

return M
