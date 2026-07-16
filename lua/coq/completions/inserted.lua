local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local debug_m = require "coq.lib.debug"
local lsp_util = require "coq.producers.lsp.util"
local snippet_preview = require "coq.producers.snippets.preview"
local tokens = require "coq.lib.index.tokens"
local txt = require "coq.lib.text"

local debug = debug_m.new "INSERTED"

local M = {}

---@class completions.Span
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class completions.EditCtx
---@field encoding string
---@field cursor_row integer
---@field col integer
---@field original_col integer
---@field cursor_line string
---@field before_inserted string
---@field after_cursor string
---@field start_line string
---@field end_line string
---@field span? completions.Span

local undojoin = function()
  vim.cmd.undojoin { mods = { emsg_silent = true } }
end

local apply_text_edits = function(...)
  undojoin()
  vim.lsp.util.apply_text_edits(...)
end

---@param settings config.Settings
---@param ctx ctx.full
---@param resolver completions.Resolver
---@param meta completions.ItemMeta
---@return lsp.TextEdit? main_edit
---@return lsp.TextEdit[] addn_edits
---@return string? snippet
M._resolve = function(settings, ctx, resolver, meta)
  local timeout_ms = math.floor(settings.clients.lsp.resolve_timeout * 1000)
  local resolved = resolver.resolve(ctx, meta, timeout_ms)

  local meta_item = meta.lsp and meta.lsp.item
  local main_edit = resolved and lsp_util.main_edit(resolved.item) or lsp_util.main_edit(meta_item)
  local addn_edits = resolved and lsp_util.addn_edits(resolved.item) or lsp_util.addn_edits(meta_item)
  local snippet = resolved and lsp_util.snippet(resolved.item) or lsp_util.snippet(meta_item)

  return main_edit, addn_edits, snippet
end

---@param buf integer
---@param encoding string
---@param cursor_row integer
---@param cursor_line string
---@param range? lsp.Range
---@return string? start_line
---@return string? end_line
---@return completions.Span? span
local resolve_range = function(buf, encoding, cursor_row, cursor_line, range)
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

  local ok_s, start_col = pcall(vim.str_byteindex, start_line, encoding, s.character, true)
  local ok_e, end_col = pcall(vim.str_byteindex, end_line, encoding, e.character, true)
  if not (ok_s and ok_e) then
    return
  end

  return start_line, end_line, { start_row = s.line, start_col = start_col, end_row = e.line, end_col = end_col }
end

---@param preview boolean
---@param ctx ctx.full
---@param i completions.Item
---@param range? lsp.Range
---@return completions.EditCtx
local edit_ctx = function(preview, ctx, i, range)
  local encoding = lsp_util.encoding(i)
  local row, col = unpack(ctx.pos)
  local cursor_row = row - 1
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, cursor_row, row, true))

  local snippet = lsp_util.snippet(i.meta.lsp and i.meta.lsp.item)
  local inserted = preview and "" or ((snippet and i.abbr) or i.word or "")
  local first_nl = string.find(inserted, "[\r\n]")
  local first_line_len = first_nl and (first_nl - 1) or #inserted
  local original_col = math.max(0, col - first_line_len)

  local start_line, end_line, span = resolve_range(ctx.buf, encoding, cursor_row, line, range)

  return {
    encoding = encoding,
    cursor_row = cursor_row,
    col = col,
    original_col = original_col,
    cursor_line = line,
    before_inserted = string.sub(line, 1, original_col),
    after_cursor = string.sub(line, col + 1),
    start_line = start_line or line,
    end_line = end_line or line,
    span = span,
  }
end

---@param iskeyword table<integer, integer>
---@param e_ctx completions.EditCtx
---@param prefix_word string
---@param suffix_word string
---@return completions.Span
M._fallback_span = function(iskeyword, e_ctx, prefix_word, suffix_word)
  local start_col = #e_ctx.before_inserted
    - math.max(
      #tokens.trailing_keyword_before(iskeyword, e_ctx.before_inserted),
      txt.prefix_overlap(e_ctx.before_inserted, prefix_word)
    )
  local end_col = e_ctx.col
    + math.max(
      #tokens.leading_keyword(iskeyword, e_ctx.after_cursor),
      txt.suffix_overlap(e_ctx.after_cursor, suffix_word)
    )

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
  local snippet = lsp_util.snippet(i.meta.lsp and i.meta.lsp.item)
  if snippet then
    return preview and snippet_preview.preview(snippet) or ""
  end

  if range then
    ---@cast text_edit -nil
    return text_edit.newText or ""
  end
  return i.word or ""
end

---@param e_ctx completions.EditCtx
---@param replace_text string
---@return completions.Span?
M._clamp_span = function(e_ctx, replace_text)
  local span = assert(e_ctx.span)
  local start_row, start_col = span.start_row, span.start_col
  local end_row, end_col = span.end_row, span.end_col

  local inverted = start_row > end_row or (start_row == end_row and start_col > end_col)
  if inverted then
    return nil
  end

  do
    local start_past_cursor = start_row == e_ctx.cursor_row and start_col > e_ctx.col
    local start_in_inserted_region = start_row == e_ctx.cursor_row
      and start_col > e_ctx.original_col
      and start_col < e_ctx.col

    if start_past_cursor then
      start_col = e_ctx.col
    elseif start_in_inserted_region then
      start_col = e_ctx.original_col
    end
  end

  do
    local multirow_with_singleline_replace = end_row > e_ctx.cursor_row and not txt.is_multiline(replace_text)
    local end_in_inserted_region = end_row == e_ctx.cursor_row and end_col >= e_ctx.original_col and end_col < e_ctx.col

    if multirow_with_singleline_replace then
      end_row, end_col = e_ctx.cursor_row, e_ctx.col
    elseif end_in_inserted_region then
      end_col = e_ctx.col
    end
  end

  return { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col }
end

---@param preview boolean
---@param ctx ctx.full
---@param i completions.Item
---@param main lsp.TextEdit?
---@return completions.Span span
---@return completions.EditCtx e_ctx
---@return string replace_text
M.span = function(preview, ctx, i, main)
  local range = main and main.range
  local e_ctx = edit_ctx(preview, ctx, i, range)
  if not e_ctx.span then
    main, range = nil, nil
  end

  local replace_text = M._replacement_text(preview, i, range, main)

  local is_snippet = lsp_util.snippet(i.meta.lsp and i.meta.lsp.item) and not preview
  local prefix_word = is_snippet and (i.word or "") or replace_text
  local suffix_word = is_snippet and "" or replace_text

  local span = e_ctx.span and M._clamp_span(e_ctx, replace_text)
    or M._fallback_span(tokens.parse_charset(ctx.iskeyword), e_ctx, prefix_word, suffix_word)

  return span, e_ctx, replace_text
end

---@param ctx ctx.full
---@param i completions.Item
---@param main lsp.TextEdit?
---@return lsp.TextEdit
M._main_edit = function(ctx, i, main)
  local span, e_ctx, replace_text = M.span(false, ctx, i, main)
  local end_line = span.end_row == e_ctx.cursor_row and e_ctx.cursor_line or e_ctx.end_line

  local start_col = math.min(span.start_col, #e_ctx.start_line)
  local end_col = math.min(span.end_col, #end_line)

  return {
    range = {
      start = {
        line = span.start_row,
        character = vim.str_utfindex(e_ctx.start_line, e_ctx.encoding, start_col, true),
      },
      ["end"] = {
        line = span.end_row,
        character = vim.str_utfindex(end_line, e_ctx.encoding, end_col, true),
      },
    },
    newText = replace_text,
  }
end

---@param ctx ctx.full
---@param i completions.Item
---@param main lsp.TextEdit?
---@param additional_edits lsp.TextEdit[]
M._apply_edits = function(ctx, i, main, additional_edits)
  local enc = lsp_util.encoding(i)
  local edit = M._main_edit(ctx, i, main)
  local all_edits = vim.list_extend({ edit }, additional_edits)
  apply_text_edits(all_edits, ctx.buf, enc)
end

---@param ctx ctx.full
---@param body string
M._apply_snippet = function(ctx, body)
  undojoin()
  local ok, err = pcall(vim.snippet.expand, body)
  if ok then
    return
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(ctx.win))
  apply_text_edits({
    {
      range = {
        start = { line = row - 1, character = col },
        ["end"] = { line = row - 1, character = col },
      },
      newText = body,
    },
  }, ctx.buf, "utf-8")

  vim.notify(err, vim.log.levels.WARN)
end

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param settings config.Settings
---@param ctx ctx.full
---@param resolver completions.Resolver
---@param i completions.Item
---@return true?
M.apply = function(settings, ctx, resolver, i)
  local main, addn_edits, snippet = M._resolve(settings, ctx, resolver, i.meta)
  atools.scheduled()
  if not context.still_valid(ctx) then
    return
  end

  debug.notify(vim.inspect { main = main, addn_edits = addn_edits, snippet = snippet })
  debug.buf(ctx.buf, "pre-apply_edits")
  M._apply_edits(ctx, i, main, addn_edits)
  debug.buf(ctx.buf, "post-apply_edits")

  if snippet then
    M._apply_snippet(ctx, snippet)
    debug.buf(ctx.buf, "post-snippet.expand")
  end

  if i.meta.lsp and i.meta.lsp.item and i.meta.lsp.item.command then
    lsp_util.exec_command(ctx, i.meta.lsp)
    debug.buf(ctx.buf, "post-command")
  end

  return true
end

return M
