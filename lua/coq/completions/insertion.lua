local broadcast = require "coq.lib.channels.broadcast"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local resolve = require "coq.completions.resolve"

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param i completions.Item
local apply = function(i)
  local meta = i.meta
  local buf = vim.api.nvim_get_current_buf()
  local lsp = meta.lsp or {}

  if #(lsp.additional_text_edits or {}) == 0 then
    local tick = vim.b[buf].changedtick
    local extra = resolve.resolve(i)
    if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].changedtick ~= tick then
      return
    end

    if extra then
      lsp = vim.tbl_extend("force", lsp, extra)
    end
  end

  local text_edit = lsp.item and lsp.item.textEdit
  local range = text_edit and (text_edit.range or text_edit.replace)
  local encoding = lsp.position_encoding or "utf-16"
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  if range then
    ---@cast text_edit -nil
    local character = vim.str_utfindex(vim.api.nvim_get_current_line(), encoding, col)
    vim.lsp.util.apply_text_edits({
      {
        range = { start = range.start, ["end"] = { line = row - 1, character = character } },
        newText = meta.snippet and "" or (text_edit.newText or ""),
      },
    }, 0, encoding)
  elseif meta.snippet then
    local inserted = i.abbr or i.word
    vim.api.nvim_buf_set_text(0, row - 1, col - #inserted, row - 1, col, { "" })
  end

  if lsp.additional_text_edits then
    vim.lsp.util.apply_text_edits(lsp.additional_text_edits, 0, encoding)
  end

  if meta.snippet then
    vim.snippet.expand(meta.snippet)
  end

  if lsp.command then
    resolve.exec_command(lsp)
  end
end

local M = {}

---@param iter producers.SearchIter
M.complete = function(iter)
  local items = {}
  for i in iter do
    ---@cast i completions.Item
    table.insert(items, item.to_nvim(i))
  end

  local before = string.sub(vim.api.nvim_get_current_line(), 1, vim.api.nvim_win_get_cursor(0)[2])
  local start = string.find(before, "[%w_]+$") or (#before + 1)
  vim.fn.complete(start, items)
end

---@param n async.Nursery
M.bind = function(n)
  local events = broadcast.new()

  vim.api.nvim_create_autocmd("CompleteDone", {
    group = lib.group,
    callback = function()
      events.replace(vim.v.completed_item)
    end,
  })

  n.spawn(function(defer)
    local iter = events.subscribe()
    defer(iter.close)

    for completed in iter do
      ---@cast completed vim.v.completed_item
      local user_data = completed.user_data
      if type(user_data) == "table" then
        ---@cast user_data completions.Item
        apply(user_data)
      end
    end
  end)
end

return M
