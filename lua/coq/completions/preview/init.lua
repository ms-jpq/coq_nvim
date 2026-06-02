local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local lib = require "coq.lib"
local show = require "coq.completions.preview.show"
local txt = require "coq.lib.text"

local NS = vim.api.nvim_create_namespace "coq.preview"

---@param buf integer
local clear = function(buf)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  show.close()
end

---@param i completions.Item
---@return string
local insertion_text = function(i)
  if i.meta.snippet then
    return i.meta.snippet
  end
  local lsp_item = i.meta.lsp and i.meta.lsp.item
  if lsp_item and lsp_item.textEdit and lsp_item.textEdit.newText then
    return lsp_item.textEdit.newText
  end
  return i.word or ""
end

---@param ctx ctx.base
---@param ghost config.GhostText
---@param i completions.Item
local show_ghost = function(ctx, ghost, i)
  if not ghost.enabled then
    return
  end

  local text = insertion_text(i)
  if text == "" then
    return
  end

  local row, col = unpack(ctx.pos)
  local lhs, rhs = unpack(ghost.context)

  local lines = vim.iter(txt.splitlines(text)):totable()
  local first = lhs .. lines[1] .. (#lines == 1 and rhs or "")
  local rest = vim
    .iter(async.wrap(function()
      for k = 2, #lines do
        local content = lines[k] .. (k == #lines and rhs or "")
        coroutine.yield { { content, ghost.highlight_group } }
      end
    end))
    :totable()

  vim.api.nvim_buf_set_extmark(ctx.buf, NS, row - 1, col, {
    virt_text = { { first, ghost.highlight_group } },
    virt_text_pos = "overlay",
    virt_lines = #rest > 0 and rest or nil,
    hl_mode = "combine",
  })
end

---@param ev completions.PumEvent
---@return completions.PumChangedEvent?
---@return completions.Item?
local item_of = function(ev)
  if ev.kind ~= "changed" then
    return nil, nil
  end
  ---@cast ev completions.PumChangedEvent

  local item = ev.completed_item and ev.completed_item.user_data
  if type(item) ~= "table" or not item.word then
    return nil, nil
  end
  ---@cast item completions.Item
  return ev, item
end

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param resolver completions.Resolver
---@param pum channels.Broadcast<completions.PumEvent>
M.bind = function(n, settings, resolver, pum)
  if settings.keymap.bigger_preview then
    local esc = vim.keycode "<c-e>"
    vim.keymap.set({ "i" }, settings.keymap.bigger_preview, function()
      local buf = show.active_buf()
      if not buf then
        return settings.keymap.bigger_preview
      end

      n.spawn(lib.with_reporting(function()
        atools.scheduled()
        show.close()
        show.promote(buf)
      end))

      return esc
    end, { expr = true, noremap = true })
  end

  events.subscribe_latest(n, pum, function(ev)
    local ctx = context.base()
    clear(ctx.buf)
    local changed_ev, item = item_of(ev)
    if item then
      show_ghost(ctx, settings.display.ghost_text, item)
      if changed_ev then
        show.show(ctx, settings, resolver, changed_ev, item)
      end
    end
  end)
end

return M
