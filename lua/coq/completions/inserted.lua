local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local lsp_util = require "coq.producers.lsp.util"
local tokens = require "coq.lib.index.tokens"

local DEFAULT_ENCODING = "utf-16"

local M = {}

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

---@class completions.EditCtx
---@field cursor_row integer
---@field col integer
---@field before_inserted string
---@field after_cursor string
---@field start_row integer
---@field start_line string
---@field end_row integer
---@field end_line string

---@param ctx ctx.full
---@param range? lsp.Range
---@return boolean
local range_in_bounds = function(ctx, range)
  if not range then
    return false
  end
  local cursor_row = ctx.pos[1] - 1
  local line_count = vim.api.nvim_buf_line_count(ctx.buf)
  local s, e = range.start, range["end"]
  return s.line >= 0 and s.line <= cursor_row and e and e.line >= s.line and e.line < line_count
end

---@param ctx ctx.full
---@param i completions.Item
---@param range? lsp.Range
---@return completions.EditCtx
local edit_ctx = function(ctx, i, range)
  local row, col = unpack(ctx.pos)
  local cursor_row = row - 1
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, cursor_row, row, true))

  local inserted = (i.meta.snippet and i.abbr) or i.word or ""
  local original_col = math.max(0, col - #inserted)

  local read_line = function(r)
    return (r == cursor_row) and line or (vim.api.nvim_buf_get_lines(ctx.buf, r, r + 1, true)[1] or "")
  end

  local start_row = (range and range.start.line) or cursor_row
  local end_row = (range and range["end"] and range["end"].line) or cursor_row

  return {
    cursor_row = cursor_row,
    col = col,
    before_inserted = string.sub(line, 1, original_col),
    after_cursor = string.sub(line, col + 1),
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

---@param haystack string
---@param needle string
---@return integer
local prefix_overlap = function(haystack, needle)
  local cap = math.min(#haystack, #needle)
  for n = cap, 1, -1 do
    if string.sub(needle, 1, n) == string.sub(haystack, #haystack - n + 1) then
      return n
    end
  end
  return 0
end

---@param haystack string
---@param needle string
---@return integer
local suffix_overlap = function(haystack, needle)
  local cap = math.min(#haystack, #needle)
  for n = cap, 1, -1 do
    if string.sub(needle, #needle - n + 1) == string.sub(haystack, 1, n) then
      return n
    end
  end
  return 0
end

---@param iskeyword lib.Set<integer>
---@param enc string
---@param e_ctx completions.EditCtx
---@param text_edit? lsp.TextEdit | lsp.InsertReplaceEdit
---@param word string
---@return completions.Span
M._span = function(iskeyword, enc, e_ctx, text_edit, word)
  local range = text_edit and (text_edit.range or text_edit.replace)
  local insert_end = text_edit and text_edit.insert and text_edit.insert["end"]
  local range_end = range and range["end"]

  local start_col = (range and vim.str_byteindex(e_ctx.start_line, enc, range.start.character, false))
    or (
      #e_ctx.before_inserted
      - math.max(
        #tokens.trailing_keyword_before(iskeyword, e_ctx.before_inserted),
        prefix_overlap(e_ctx.before_inserted, word)
      )
    )

  local end_row, end_col = (function()
    if insert_end and range_end and insert_end.line == e_ctx.cursor_row then
      if range_end.line == e_ctx.cursor_row then
        local units = math.max(0, range_end.character - insert_end.character)
        return e_ctx.cursor_row, e_ctx.col + vim.str_byteindex(e_ctx.after_cursor, enc, units, false)
      end
      return e_ctx.end_row, vim.str_byteindex(e_ctx.end_line, enc, range_end.character, false)
    end

    local end_col = e_ctx.col
      + math.max(#tokens.leading_keyword(iskeyword, e_ctx.after_cursor), suffix_overlap(e_ctx.after_cursor, word))
    return e_ctx.cursor_row, end_col
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

---@param enc string
---@param span completions.Span
---@param buf integer
---@param text string
---@return lsp.TextEdit
local span_to_text_edit = function(enc, span, buf, text)
  local start_line = vim.api.nvim_buf_get_lines(buf, span.start_row, span.start_row + 1, true)[1] or ""
  local end_line = span.end_row == span.start_row and start_line
    or (vim.api.nvim_buf_get_lines(buf, span.end_row, span.end_row + 1, true)[1] or "")

  return {
    range = {
      start = {
        line = span.start_row,
        character = vim.str_utfindex(start_line, enc, span.start_col, true),
      },
      ["end"] = {
        line = span.end_row,
        character = vim.str_utfindex(end_line, enc, span.end_col, true),
      },
    },
    newText = text,
  }
end

---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return lsp.TextEdit
M._main_edit = function(ctx, i, lsp)
  local enc = lsp.position_encoding or DEFAULT_ENCODING
  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)

  if range and not range_in_bounds(ctx, range) then
    text_edit, range = nil, nil
  end

  local e_ctx = edit_ctx(ctx, i, range)
  local text = M._replacement(i, range, text_edit)
  local span = M._span(ctx.iskeyword, enc, e_ctx, text_edit, text)

  return span_to_text_edit(enc, span, ctx.buf, text)
end

---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@param additional_edits lsp.TextEdit[]
M._apply_edits = function(ctx, i, lsp, additional_edits)
  local enc = lsp.position_encoding or DEFAULT_ENCODING
  local main_edit = M._main_edit(ctx, i, lsp)
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
