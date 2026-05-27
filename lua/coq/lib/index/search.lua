---@class index.SearchContext
---@field win integer
---@field buf integer
---@field pos [integer, integer]
---@field filetype string
---@field filename string
---@field cword string
---@field cexpr string
---@field tabstop integer
---@field expandtab boolean
---@field iskeyword string
---@field linesep string
---@field comment [string, string]
---@field line_count integer
---@field line string
---@field line_before string
---@field line_after string
---@field utf16_col integer
---@field utf32_col integer

local M = {}

---@return index.SearchContext
M.ctx = function()
  local ctx = {}

  do
    ctx.win = vim.api.nvim_get_current_win()
    ctx.buf = vim.api.nvim_win_get_buf(ctx.win)
    ctx.pos = vim.api.nvim_win_get_cursor(ctx.win)
  end

  local bo = vim.bo[ctx.buf]

  do
    ctx.filetype = bo.filetype
    ctx.filename = vim.api.nvim_buf_get_name(ctx.buf)
  end

  do
    ctx.cword = vim.fn.expand "<cword>"
    ctx.cexpr = vim.fn.expand "<cexpr>"
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
    local _, col = unpack(ctx.pos)

    ctx.line_count = vim.api.nvim_buf_line_count(ctx.buf)
    ctx.line = vim.api.nvim_get_current_line()
    ctx.line_before = ctx.line:sub(1, col)
    ctx.line_after = ctx.line:sub(col + 1)
  end

  do
    ctx.utf16_col = vim.str_utfindex(ctx.line_before, "utf-16")
    ctx.utf32_col = vim.str_utfindex(ctx.line_before, "utf-32")
  end

  return ctx
end

---@param db producer.Producer
M.search = function(db)
  return db.search(M.ctx())
end

return M
