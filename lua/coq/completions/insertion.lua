local broadcast = require "coq.lib.channels.broadcast"
local context = require "coq.lib.context"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local resolve = require "coq.completions.resolve"

local DEFAULT_ENCODING = "utf-16"
local TAIL_RE = vim.regex [[\V\k\+\$]]
local HEAD_RE = vim.regex [[\V\k\+]]

---@param ctx ctx.base
---@param i completions.Item
---@param lsp completions.ItemLspMeta
---@return integer del_start
---@return integer del_end
---@return string replacement
local word_range = function(ctx, i, lsp)
  local row, col = unpack(ctx.pos)
  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)
  local line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, true))

  local inserted = (i.meta.snippet and i.abbr) or i.word or ""
  local original_col = col - #inserted

  local del_start, del_end = unpack(vim.api.nvim_buf_call(ctx.buf, function()
    local before_inserted = string.sub(line, 1, original_col)
    local after_cursor = string.sub(line, col + 1)
    local preceding = TAIL_RE:match_str(before_inserted) or original_col
    local start, end_ = HEAD_RE:match_str(after_cursor)

    if range and range.start.line == row - 1 then
      preceding = vim.str_byteindex(line, lsp.position_encoding or DEFAULT_ENCODING, range.start.character)
    end
    return { preceding, col + ((start == 0) and end_ or 0) }
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

  return del_start, del_end, replacement
end

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param ctx ctx.base
---@param i completions.Item
local apply = function(ctx, i)
  local row = unpack(ctx.pos)
  local meta = i.meta
  local lsp = meta.lsp or {}

  if #(lsp.additional_text_edits or {}) == 0 then
    local extra = resolve.resolve(ctx, i)
    if not context.still_valid(ctx) then
      return
    end
    if extra then
      lsp = vim.tbl_extend("force", lsp, extra)
      ---@cast lsp completions.ItemLspMeta
    end
  end

  local del_start, del_end, replacement = word_range(ctx, i, lsp)
  vim.api.nvim_buf_set_text(ctx.buf, row - 1, del_start, row - 1, del_end, { replacement })

  if lsp.additional_text_edits then
    vim.lsp.util.apply_text_edits(lsp.additional_text_edits, ctx.buf, lsp.position_encoding or DEFAULT_ENCODING)
  end
  if meta.snippet then
    vim.snippet.expand(meta.snippet)
  end
  if lsp.command then
    resolve.exec_command(ctx, lsp)
  end
end

local M = {}

---@param ctx ctx.full
---@param iter producers.SearchIter
M.complete = function(ctx, iter)
  local items = {}
  for i in iter do
    ---@cast i completions.Item
    table.insert(items, item.to_nvim(i))
  end

  local start = #ctx.line_before + 1
  vim.fn.complete(start, items)
end

---@param n async.Nursery
M.bind = function(n)
  local events = broadcast.new()

  vim.api.nvim_create_autocmd({ "CompleteDone" }, {
    group = lib.group,
    callback = function()
      events.replace(vim.v.completed_item, context.base())
    end,
  })

  n.spawn(function(defer)
    local iter = events.subscribe()
    defer(iter.close)

    for completed, ctx in iter do
      ---@cast completed vim.v.completed_item
      ---@cast ctx ctx.base
      local user_data = completed.user_data
      if type(user_data) == "table" then
        ---@cast user_data completions.Item
        apply(ctx, user_data)
      end
    end
  end)
end

return M
