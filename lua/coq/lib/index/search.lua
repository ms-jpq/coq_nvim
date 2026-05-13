local async = require "coq.lib.async"

local M = {}

M.ctx = function()
  local ctx = {}

  do
    ctx.handle = async.current()
    ctx.win = vim.api.nvim_get_current_win()
    ctx.buf = vim.api.nvim_win_get_buf(ctx.win)
    ctx.pos = vim.api.nvim_win_get_cursor(ctx.win)
  end

  local bo = vim.bo[ctx.buf]

  do
    ctx.scr_col = vim.fn.screencol()
    ctx.win_size = vim.api.nvim_win_get_height(ctx.win) / 2
  end

  do
    ctx.filetype = bo.filetype
    ctx.filename = vim.api.nvim_buf_get_name(ctx.buf)
  end

  do
    ctx.cword = vim.fn.expand "<cword>"
    ctx.cexpr = vim.fn.expand "<cexpr>"
    ctx.line_count = vim.api.nvim_buf_line_count(ctx.buf)
  end

  do
    local lhs, rhs = bo.commentstring:match "(.*)%%s(.*)"
    local fileformat = bo.fileformat

    ctx.tabstop = bo.tabstop
    ctx.expandtab = bo.expandtab
    ctx.iskeyword = bo.iskeyword

    ctx.linesep = ({ unix = "\n", dos = "\r\n", mac = "\r" })[fileformat]
    ctx.comment = { lhs or "", rhs or "" }
  end

  do
    local row, col = ctx.pos[1] - 1, ctx.pos[2]
    local lo = math.max(0, row - ctx.win_size)
    local hi = math.min(ctx.line_count, row + ctx.win_size + 1)
    local r = row - lo

    ctx.lines = vim.api.nvim_buf_get_lines(ctx.buf, lo, hi, false)
    ctx.line = ctx.lines[r + 1] or ""
    ctx.lines_before = vim.list_slice(ctx.lines, 1, r)
    ctx.lines_after = vim.list_slice(ctx.lines, r + 2)
    ctx.line_before = ctx.line:sub(1, col)
    ctx.line_after = ctx.line:sub(col + 1)
  end

  do
    ctx.utf16_col = vim.str_utfindex(ctx.line_before, "utf-16")
    ctx.utf32_col = vim.str_utfindex(ctx.line_before, "utf-32")
  end

  return ctx
end

M.search = function(db)
  return db.search(M.ctx())
end

return M
