local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local events = require "coq.completions.events"
local nvim_options = require "coq.nvim_options"
local show = require "coq.completions.preview.show"

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
    vim.keymap.set({ "i" }, settings.keymap.bigger_preview, function()
      local buf = show.active_buf()
      if not buf then
        return settings.keymap.bigger_preview
      end

      n.spawn(errs.with_reporting(function()
        atools.scheduled()
        show.close()
        show.promote(buf)
      end))

      return nvim_options.CE
    end, { expr = true, noremap = true })
  end

  events.subscribe_latest(n, pum, function(ev)
    local ctx = context.base()
    show.close()
    local changed_ev, item = item_of(ev)
    if changed_ev and item then
      show.show(ctx, settings, resolver, changed_ev, item)
    end
  end)
end

return M
