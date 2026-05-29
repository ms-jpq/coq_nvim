local broadcast = require "coq.lib.channels.broadcast"
local context = require "coq.lib.context"
local lib = require "coq.lib"

---@class completions.preview.ChangedEvent
---@field kind "changed"
---@field item vim.v.completed_item

---@class completions.preview.ClearEvent
---@field kind "clear"

---@alias completions.preview.Event completions.preview.ChangedEvent | completions.preview.ClearEvent

local NS = vim.api.nvim_create_namespace "coq.preview"

---@param buf integer
local clear = function(buf)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
end

---@param ctx ctx.base
---@param ghost config.GhostText
---@param i completions.Item
local show_ghost = function(ctx, ghost, i)
  if not ghost.enabled then
    return
  end
  local text = i.meta.snippet and i.abbr or i.word
  if not text or text == "" then
    return
  end

  local row, col = unpack(ctx.pos)
  local inline = ghost.context[1] .. text .. ghost.context[2]

  vim.api.nvim_buf_set_extmark(ctx.buf, NS, row - 1, col, {
    virt_text = { { inline, ghost.highlight_group } },
    virt_text_pos = "overlay",
    hl_mode = "combine",
  })
end

---@param i completions.Item
local show_doc = function(i) end

local M = {}

---@param n async.Nursery
---@param settings config.Settings
M.bind = function(n, settings)
  ---@type channels.Broadcast<completions.preview.Event>
  local events = broadcast.new()

  vim.api.nvim_create_autocmd("CompleteChanged", {
    group = lib.group,
    callback = function()
      events.replace({ kind = "changed", item = vim.v.event.completed_item }, context.base())
    end,
  })

  vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave" }, {
    group = lib.group,
    callback = function()
      events.replace({ kind = "clear" }, context.base())
    end,
  })

  n.spawn(function(defer)
    local iter = events.subscribe()
    defer(iter.close)

    for ev, ctx in iter do
      ---@cast ctx ctx.base
      clear(ctx.buf)

      if ev.kind == "changed" and ev.item and next(ev.item) then
        ---@type completions.Item?
        local item = ev.item.user_data
        if type(item) == "table" and item.word then
          show_ghost(ctx, settings.display.ghost_text, item)
          show_doc(item)
        end
      end
    end
  end)
end

return M
