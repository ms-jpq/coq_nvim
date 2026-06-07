local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local lsp_util = require "coq.producers.lsp.util"
local snippet_preview = require "coq.producers.snippets.preview"
local tokens = require "coq.lib.index.tokens"
local txt = require "coq.lib.text"

local DEFAULT_ENCODING = "utf-16"

local M = {}

M.prefix_overlap = txt.prefix_overlap
M.suffix_overlap = txt.suffix_overlap

---@param lsp completions.ItemLspMeta?
---@return lsp.TextEdit | lsp.InsertReplaceEdit?
---@return lsp.Range?
M.text_edit = function(lsp)
  local te = lsp and lsp.item and lsp.item.textEdit
  return te, te and (te.range or te.replace)
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

---@class completions.Span
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class completions.EditCtx
---@field cursor_row integer
---@field col integer
---@field before_inserted string
---@field after_cursor string
---@field start_line string
---@field end_line string
---@field span? completions.Span

---@param buf integer
---@param enc string
---@param cursor_row integer
---@param cursor_line string
---@param range? lsp.Range
---@return string? start_line
---@return string? end_line
---@return completions.Span? span
local resolve_range = function(buf, enc, cursor_row, cursor_line, range)
  if not range then
    return
  end
  local s, e = range.start, range["end"]
  local line_count = vim.api.nvim_buf_line_count(buf)
  if not (s.line >= 0 and s.line <= cursor_row and e and e.line >= s.line and e.line < line_count) then
    return
  end

  local read = function(r)
    return (r == cursor_row) and cursor_line or (vim.api.nvim_buf_get_lines(buf, r, r + 1, true)[1] or "")
  end
  local start_line = read(s.line)
  local end_line = (e.line == s.line) and start_line or read(e.line)

  local ok_s, start_col = pcall(vim.str_byteindex, start_line, enc, s.character, true)
  local ok_e, end_col = pcall(vim.str_byteindex, end_line, enc, e.character, true)
  if not (ok_s and ok_e) then
    return
  end

  return start_line, end_line, { start_row = s.line, start_col = start_col, end_row = e.line, end_col = end_col }
end

---@param preview boolean
---@param ctx ctx.full
---@param i completions.Item
---@param enc string
---@param range? lsp.Range
---@return completions.EditCtx
local edit_ctx = function(preview, ctx, i, enc, range)
  local row, col = unpack(ctx.pos)
  local cursor_row = row - 1
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, cursor_row, row, true))

  local inserted = preview and "" or ((i.meta.snippet and i.abbr) or i.word or "")
  local original_col = math.max(0, col - #inserted)

  local start_line, end_line, span = resolve_range(ctx.buf, enc, cursor_row, line, range)

  return {
    cursor_row = cursor_row,
    col = col,
    before_inserted = string.sub(line, 1, original_col),
    after_cursor = string.sub(line, col + 1),
    start_line = start_line or line,
    end_line = end_line or line,
    span = span,
  }
end

---@param iskeyword lib.Set<integer>
---@param e_ctx completions.EditCtx
---@param word string
---@return completions.Span
M._fallback_span = function(iskeyword, e_ctx, word)
  local start_col = #e_ctx.before_inserted
    - math.max(
      #tokens.trailing_keyword_before(iskeyword, e_ctx.before_inserted),
      M.prefix_overlap(e_ctx.before_inserted, word)
    )
  local end_col = e_ctx.col
    + math.max(#tokens.leading_keyword(iskeyword, e_ctx.after_cursor), M.suffix_overlap(e_ctx.after_cursor, word))

  return {
    start_row = e_ctx.cursor_row,
    start_col = start_col,
    end_row = e_ctx.cursor_row,
    end_col = end_col,
  }
end

---@param preview boolean
---@param i completions.Item
---@param range? lsp.Range
---@param text_edit? lsp.TextEdit | lsp.InsertReplaceEdit
---@return string
M._replacement_text = function(preview, i, range, text_edit)
  if i.meta.snippet then
    return preview and snippet_preview.preview(i.meta.snippet) or ""
  end

  if range then
    ---@cast text_edit -nil
    return text_edit.newText or ""
  end
  return i.word or ""
end

---@param preview boolean
---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return completions.Span span
---@return completions.EditCtx e_ctx
---@return string enc
---@return string replace_text
M.span = function(preview, ctx, i, lsp)
  local text_edit, range = M.text_edit(lsp)

  local enc = lsp.position_encoding or DEFAULT_ENCODING
  local e_ctx = edit_ctx(preview, ctx, i, enc, range)
  if not e_ctx.span then
    text_edit, range = nil, nil
  end

  local replace_text = M._replacement_text(preview, i, range, text_edit)
  local match_text = (i.meta.snippet and (i.word or "")) or replace_text
  local span = e_ctx.span or M._fallback_span(ctx.iskeyword, e_ctx, match_text)

  return span, e_ctx, enc, replace_text
end

---@param ctx ctx.full
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return lsp.TextEdit
M._main_edit = function(ctx, i, lsp)
  local span, e_ctx, enc, replace_text = M.span(false, ctx, i, lsp)
  return {
    range = {
      start = {
        line = span.start_row,
        character = vim.str_utfindex(e_ctx.start_line, enc, span.start_col, true),
      },
      ["end"] = {
        line = span.end_row,
        character = vim.str_utfindex(e_ctx.end_line, enc, span.end_col, true),
      },
    },
    newText = replace_text,
  }
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
