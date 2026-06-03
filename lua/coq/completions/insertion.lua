local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local events = require "coq.completions.events"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local lsp_util = require "coq.producers.lsp.util"
local ranker_m = require "coq.lib.index.rank.ranker"
local tokens = require "coq.lib.index.tokens"
local topk_m = require "coq.lib.index.rank.topk"
local txt = require "coq.lib.text"

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
    kw_before_col = original_col - #tokens.trailing_keyword_before(ctx.kw, before_inserted),
    kw_after_len = #tokens.leading_keyword(ctx.kw, after_cursor),
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

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param settings config.Settings
---@param ctx ctx.full
---@param resolver completions.Resolver
---@param i completions.Item
---@return true?
local apply = function(settings, ctx, resolver, i)
  local meta = i.meta
  local lsp = meta.lsp or {}

  local edits = lsp.item and lsp.item.additionalTextEdits
  if #(edits or {}) == 0 then
    local timeout_ms = math.floor(settings.clients.lsp.resolve_timeout * 1000)
    lsp = resolver.resolve(ctx, i, timeout_ms) or lsp
    if not context.still_valid(ctx) then
      return
    end
    edits = lsp.item and lsp.item.additionalTextEdits
  end

  do
    local edit = M._word_range(ctx, i, lsp)
    local lines = vim.iter(txt.splitlines(edit.text)):totable()
    vim.api.nvim_buf_set_text(ctx.buf, edit.start_row, edit.start_col, edit.end_row, edit.end_col, lines)
  end

  if edits then
    vim.lsp.util.apply_text_edits(edits, ctx.buf, lsp.position_encoding or DEFAULT_ENCODING)
  end

  if meta.snippet then
    errs.with_reporting(vim.snippet.expand)(meta.snippet)
  end

  if lsp.item and lsp.item.command then
    lsp_util.exec_command(ctx, lsp)
  end

  return true
end

---@param ctx ctx.full
---@param settings config.Settings
---@param ranker index.Ranker
---@param iter lib.Iterator<completions.Item>
M.complete = function(ctx, settings, ranker, iter)
  local prepared = ranker.prepare(ctx)

  local topk = topk_m.new(settings.match.max_results, item.dedup_key)
  for i in iter do
    topk.push(i, ranker_m.score(prepared, i))
  end

  local items = {}
  for i in topk.iter() do
    table.insert(items, item.to_nvim(settings.display.icons, i))
  end

  atools.scheduled()
  if not context.still_valid(ctx) or string.sub(vim.api.nvim_get_mode().mode, 1, 1) ~= "i" then
    return
  end

  local start = #ctx.line_before - #ctx.keyword_before + 1
  vim.fn.complete(start, items)
end

---@param n async.Nursery
---@param settings config.Settings
---@param resolver completions.Resolver
---@param ranker index.Ranker
---@param done channels.Broadcast<vim.v.completed_item>
---@param trigger channels.Broadcast<completions.TriggerEvent>
M.bind = function(n, settings, resolver, ranker, done, trigger)
  events.subscribe_latest(n, done, function(completed)
    local user_data = completed.user_data
    if type(user_data) ~= "table" then
      return
    end

    ---@cast user_data completions.Item
    local ctx = context.full()
    local filter = user_data.meta.filter or user_data.word
    if apply(settings, ctx, resolver, user_data) and filter then
      ranker.inserted(filter)
      if user_data.meta.path and user_data.kind == "Folder" then
        trigger.replace { manual = false }
      end
    end
  end)
end

return M
