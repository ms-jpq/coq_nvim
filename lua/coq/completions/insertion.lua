local broadcast = require "coq.lib.channels.broadcast"
local context = require "coq.lib.context"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local resolve = require "coq.completions.resolve"

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param ctx ctx.base
---@param i completions.Item
local apply = function(ctx, i)
  local meta = i.meta
  local lsp = meta.lsp or {}

  if #(lsp.additional_text_edits or {}) == 0 then
    local extra = resolve.resolve(ctx, i)
    if not context.valid(ctx) then
      return
    end

    if extra then
      lsp = vim.tbl_extend("force", lsp, extra)
    end
  end

  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)
  local encoding = lsp.position_encoding or "utf-16"
  local row, col = unpack(ctx.pos)

  if range then
    ---@cast text_edit -nil
    local line = vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, false)[1] or ""
    local character = vim.str_utfindex(line, encoding, col)
    vim.lsp.util.apply_text_edits({
      {
        range = { start = range.start, ["end"] = { line = row - 1, character = character } },
        newText = meta.snippet and "" or (text_edit.newText or ""),
      },
    }, ctx.buf, encoding)
  elseif meta.snippet then
    local inserted = i.abbr or i.word
    vim.api.nvim_buf_set_text(ctx.buf, row - 1, col - #inserted, row - 1, col, { "" })
  end

  if lsp.additional_text_edits then
    vim.lsp.util.apply_text_edits(lsp.additional_text_edits, ctx.buf, encoding)
  end

  if meta.snippet then
    vim.snippet.expand(meta.snippet)
  end

  if lsp.command then
    resolve.exec_command(ctx, lsp)
  end
end

local M = {}

---@param ctx ctx.base
---@param iter producers.SearchIter
M.complete = function(ctx, iter)
  local items = {}
  for i in iter do
    ---@cast i completions.Item
    table.insert(items, item.to_nvim(i))
  end

  local row, col = unpack(ctx.pos)
  local line = vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, false)[1] or ""
  local before = string.sub(line, 1, col)
  local start = string.find(before, "[%w_]+$") or (#before + 1)
  vim.fn.complete(start, items)
end

---@param n async.Nursery
M.bind = function(n)
  local events = broadcast.new()

  vim.api.nvim_create_autocmd("CompleteDone", {
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
