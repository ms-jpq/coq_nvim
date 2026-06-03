local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local events = require "coq.completions.events"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local lsp_util = require "coq.producers.lsp.util"
local ranker_m = require "coq.lib.index.rank.ranker"
local topk_m = require "coq.lib.index.rank.topk"
local txt = require "coq.lib.text"

local DEFAULT_ENCODING = "utf-16"

---@param ctx ctx.base
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return integer start_row
---@return integer start_col
---@return integer end_row
---@return integer end_col
---@return string replacement
local word_range = function(ctx, i, lsp)
  local row, col = unpack(ctx.pos)
  local end_row = row - 1
  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, end_row, row, true))

  local inserted = (i.meta.snippet and i.abbr) or i.word or ""
  local original_col = math.max(0, col - #inserted)
  local before_inserted = string.sub(line, 1, original_col)
  local after_cursor = string.sub(line, col + 1)

  local start_row = lib.clamp(0, (range and range.start.line) or end_row, end_row)
  local start_line = (start_row == end_row) and line
    or vim.api.nvim_buf_get_lines(ctx.buf, start_row, start_row + 1, true)[1]

  local start_col, end_col = unpack(vim.api.nvim_buf_call(ctx.buf, function()
    local s, e = vim.regex([[\V\k\+]]):match_str(after_cursor)
    local preceding = range
        and vim.str_byteindex(start_line, lsp.position_encoding or DEFAULT_ENCODING, range.start.character)
      or (vim.regex([[\V\k\+\$]]):match_str(before_inserted) or original_col)

    return { preceding, col + ((s == 0) and e or 0) }
  end))

  local replacement = (function()
    if i.meta.snippet then
      return ""
    elseif range then
      ---@cast text_edit -nil
      return text_edit.newText or ""
    else
      return inserted
    end
  end)()

  return start_row, start_col, end_row, end_col, replacement
end

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param settings config.Settings
---@param ctx ctx.base
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
    local start_row, start_col, end_row, end_col, replacement = word_range(ctx, i, lsp)
    local lines = vim.iter(txt.splitlines(replacement)):totable()
    vim.api.nvim_buf_set_text(ctx.buf, start_row, start_col, end_row, end_col, lines)
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

local M = {}

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
    local ctx = context.base()
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
