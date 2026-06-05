local atools = require "coq.lib.atools"
local lib = require "coq.lib"

---@class ctx.base
---@field win integer
---@field buf integer
---@field pos [integer, integer]
---@field changedtick integer
---@field filetype string

---@class ctx.full: ctx.base
---@field manual boolean
---@field cwd string
---@field filename string
---@field linesep string
---@field iskeyword lib.Set<integer>
---@field isfname string
---@field wildignore string
---@field comment [string, string]
---@field line string
---@field line_before string
---@field line_after string
---@field keyword_before string
---@field keyword_before_has_upper boolean

local M = {}

---@param ctx ctx.base
---@return boolean
M.still_valid = function(ctx)
  atools.scheduled()
  return vim.api.nvim_buf_is_valid(ctx.buf) and vim.b[ctx.buf].changedtick == ctx.changedtick
end

---@return ctx.base
M.base = function()
  atools.scheduled()

  local ctx = {}

  ctx.win = vim.api.nvim_get_current_win()
  ctx.buf = vim.api.nvim_win_get_buf(ctx.win)
  ctx.pos = vim.api.nvim_win_get_cursor(ctx.win)
  ctx.changedtick = vim.b[ctx.buf].changedtick
  ctx.filetype = vim.bo[ctx.buf].filetype

  ---@cast ctx ctx.base
  return ctx
end

---@class ctx.FullOpts
---@field manual? boolean

---@param opts? ctx.FullOpts
---@return ctx.full
M.full = function(opts)
  local tokens = require "coq.lib.index.tokens"

  local ctx = M.base()
  ---@cast ctx ctx.full
  ctx.manual = (opts and opts.manual) or false
  local bo = vim.bo[ctx.buf]

  do
    ctx.cwd = lib.getcwd()
    ctx.filename = vim.api.nvim_buf_get_name(ctx.buf)
    ctx.linesep = bo.fileformat == "dos" and "\r\n" or bo.fileformat == "mac" and "\r" or "\n"
  end

  do
    local lhs, rhs = string.match(bo.commentstring, "(.*)%%s(.*)")
    ctx.iskeyword = tokens.parse_charset(bo.iskeyword)
    ctx.isfname = vim.o.isfname
    ctx.wildignore = vim.o.wildignore
    ctx.comment = { lhs or "", rhs or "" }
  end

  do
    local _, col = unpack(ctx.pos)

    ctx.line = vim.api.nvim_get_current_line()
    ctx.line_before = string.sub(ctx.line, 1, col)
    ctx.line_after = string.sub(ctx.line, col + 1)

    ctx.keyword_before = tokens.trailing_keyword_before(ctx.iskeyword, ctx.line_before)
    ctx.keyword_before_has_upper = string.find(ctx.keyword_before, "%u") ~= nil
  end

  return ctx
end

return M
