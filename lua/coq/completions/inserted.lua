local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local lib = require "coq.lib"
local lsp_util = require "coq.producers.lsp.util"
local tokens = require "coq.lib.index.tokens"

local DEFAULT_ENCODING = "utf-16"

local M = {}

---@class completions.EditCtx
---@field cursor_row integer
---@field col integer
---@field after_cursor string
---@field kw_before_col integer
---@field kw_after_len integer
---@field start_row integer
---@field start_line string
---@field end_row integer
---@field end_line string

---@param ctx ctx.full
---@param i completions.Item
---@param range? lsp.Range
---@return completions.EditCtx
local edit_ctx = function(ctx, i, range)
  local row, col = unpack(ctx.pos)
  local cursor_row = row - 1
  local line_count = vim.api.nvim_buf_line_count(ctx.buf)
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, cursor_row, row, true))

  local inserted = (i.meta.snippet and i.abbr) or i.word or ""
  local original_col = math.max(0, col - #inserted)
  local before_inserted = string.sub(line, 1, original_col)
  local after_cursor = string.sub(line, col + 1)

  local read_line = function(r)
    return (r == cursor_row) and line or (vim.api.nvim_buf_get_lines(ctx.buf, r, r + 1, true)[1] or "")
  end

  local start_row = lib.clamp(0, (range and range.start.line) or cursor_row, cursor_row)
  local end_row = (range and range["end"] and math.min(range["end"].line, line_count - 1)) or cursor_row

  return {
    cursor_row = cursor_row,
    col = col,
    after_cursor = after_cursor,
    kw_before_col = original_col - #tokens.trailing_keyword_before(ctx.iskeyword, before_inserted),
    kw_after_len = #tokens.leading_keyword(ctx.iskeyword, after_cursor),
    start_row = start_row,
    start_line = read_line(start_row),
    end_row = end_row,
    end_line = read_line(end_row),
  }
end

---@class completions.Span
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class completions.WordEdit: completions.Span
---@field text string

---@param enc string
---@param e_ctx completions.EditCtx
---@param text_edit? lsp.TextEdit | lsp.InsertReplaceEdit
---@return completions.Span
M._span = function(enc, e_ctx, text_edit)
  local range = text_edit and (text_edit.range or text_edit.replace)
  local insert_end = text_edit and text_edit.insert and text_edit.insert["end"]
  local range_end = range and range["end"]

  local start_col = (range and vim.str_byteindex(e_ctx.start_line, enc, range.start.character, false))
    or e_ctx.kw_before_col

  local end_row, end_col = (function()
    if insert_end and range_end and insert_end.line == e_ctx.cursor_row then
      if range_end.line == e_ctx.cursor_row then
        local units = math.max(0, range_end.character - insert_end.character)
        return e_ctx.cursor_row, e_ctx.col + vim.str_byteindex(e_ctx.after_cursor, enc, units, false)
      end
      return e_ctx.end_row, vim.str_byteindex(e_ctx.end_line, enc, range_end.character, false)
    end
    return e_ctx.cursor_row, e_ctx.col + e_ctx.kw_after_len
  end)()

  return { start_row = e_ctx.start_row, start_col = start_col, end_row = end_row, end_col = end_col }
end

---@param i completions.Item
---@param range? lsp.Range
---@param text_edit? lsp.TextEdit | lsp.InsertReplaceEdit
---@return string
M._replacement = function(i, range, text_edit)
  if i.meta.snippet then
    return ""
  end
  if range then
    ---@cast text_edit -nil
    return text_edit.newText or ""
  end
  return i.word or ""
end

---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return completions.WordEdit
M._word_range = function(ctx, i, lsp)
  local enc = lsp.position_encoding or DEFAULT_ENCODING
  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)

  local edit = M._span(enc, edit_ctx(ctx, i, range), text_edit) --[[@as completions.WordEdit]]
  edit.text = M._replacement(i, range, text_edit)
  return edit
end

---@param settings config.Settings
---@param ctx ctx.full
---@param resolver completions.Resolver
---@param i completions.Item
---@return completions.ItemLspMeta? lsp
---@return lsp.TextEdit[] edits
M._resolve = function(settings, ctx, resolver, i)
  local lsp = i.meta.lsp or {}
  local edits = (lsp.item and lsp.item.additionalTextEdits) or {}
  if #edits > 0 then
    return lsp, edits
  end

  local timeout_ms = math.floor(settings.clients.lsp.resolve_timeout * 1000)
  lsp = resolver.resolve(ctx, i, timeout_ms) or lsp
  edits = (lsp.item and lsp.item.additionalTextEdits) or {}

  if not context.still_valid(ctx) then
    return nil, {}
  end
  return lsp, edits
end

---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@param additional_edits lsp.TextEdit[]
M._apply_edits = function(ctx, i, lsp, additional_edits)
  local edit = M._word_range(ctx, i, lsp)
  local enc = lsp.position_encoding or DEFAULT_ENCODING
  local start_line = vim.api.nvim_buf_get_lines(ctx.buf, edit.start_row, edit.start_row + 1, true)[1] or ""
  local end_line = edit.end_row == edit.start_row and start_line
    or (vim.api.nvim_buf_get_lines(ctx.buf, edit.end_row, edit.end_row + 1, true)[1] or "")

  local main_edit = {
    range = {
      start = {
        line = edit.start_row,
        character = vim.str_utfindex(start_line, enc, edit.start_col, true),
      },
      ["end"] = {
        line = edit.end_row,
        character = vim.str_utfindex(end_line, enc, edit.end_col, true),
      },
    },
    newText = edit.text,
  }
  local all_edits = vim.list_extend({ main_edit }, additional_edits)

  vim.lsp.util.apply_text_edits(all_edits, ctx.buf, enc)
end

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param settings config.Settings
---@param ctx ctx.full
---@param resolver completions.Resolver
---@param i completions.Item
---@return true?
M.apply = function(settings, ctx, resolver, i)
  local lsp, edits = M._resolve(settings, ctx, resolver, i)
  if not lsp then
    return
  end

  M._apply_edits(ctx, i, lsp, edits)

  if i.meta.snippet then
    errs.with_reporting(vim.snippet.expand)(i.meta.snippet)
  end

  if lsp.item and lsp.item.command then
    lsp_util.exec_command(ctx, lsp)
  end

  return true
end

return M
