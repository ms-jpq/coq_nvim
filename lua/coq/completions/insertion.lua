local broadcast = require "coq.lib.channels.broadcast"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local resolve = require "coq.completions.resolve"

-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/completion.lua
---@param i completions.Item
local apply = function(i)
  local meta = i.meta
  local buf = vim.api.nvim_get_current_buf()

  if not (meta.additional_text_edits and #meta.additional_text_edits > 0) then
    local before = vim.b[buf].changedtick
    local extra = resolve.resolve(i)
    if vim.b[buf].changedtick ~= before then
      return
    end
    if extra then
      meta = vim.tbl_extend("force", meta, extra)
    end
  end

  if meta.snippet then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local inserted = i.abbr or i.word
    vim.api.nvim_buf_set_text(0, row - 1, col - #inserted, row - 1, col, { "" })
  end

  if meta.additional_text_edits then
    vim.lsp.util.apply_text_edits(meta.additional_text_edits, 0, meta.position_encoding or "utf-16")
  end

  if meta.snippet then
    vim.snippet.expand(meta.snippet)
  end

  if meta.command then
    resolve.exec_command(meta)
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
