local async = require "coq.lib.async"

local M = {}

M.ctx = function()
  local ctx = {}

  ctx.handle = async.current()
  ctx.win = vim.api.nvim_get_current_win()
  ctx.buf = vim.api.nvim_win_get_buf(ctx.win)
  ctx.cword = vim.fn.expand "<cword>"
  ctx.cexpr = vim.fn.expand "<cexpr>"

  return ctx
end

M.search = function(db)
  return db.search(M.ctx())
end

return M
