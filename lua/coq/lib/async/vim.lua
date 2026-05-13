-- Async ops that depend on vim runtime fns absent in worker threads.
-- Use coq.lib.async for worker-safe primitives.

local async = require "coq.lib.async"

return {
  scheduled = async.wrap(vim.schedule),
  system = async.wrap(vim.system),
  fn = {
    jobstart = async.wrap(function(cmd, opts, on_exit)
      opts = opts or {}
      opts.on_exit = on_exit
      vim.fn.jobstart(cmd, opts)
    end),
  },
  ui = {
    select = async.wrap(vim.ui.select),
  },
}
