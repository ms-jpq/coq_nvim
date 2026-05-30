local broadcast = require "coq.lib.channels.broadcast"
local lib = require "coq.lib"

---@class completions.PumChangedEvent
---@field kind "changed"
---@field item vim.v.completed_item

---@class completions.PumClearEvent
---@field kind "clear"

---@alias completions.PumEvent completions.PumChangedEvent | completions.PumClearEvent

---@class completions.Events
---@field trigger channels.Broadcast<nil>
---@field pum channels.Broadcast<completions.PumEvent>
---@field done channels.Broadcast<vim.v.completed_item>
---@field idle channels.Broadcast<nil>

local M = {}

---@return completions.Events
M.new = function()
  ---@type completions.Events
  local events = {
    trigger = broadcast.new(),
    pum = broadcast.new(),
    done = broadcast.new(),
    idle = broadcast.new(),
  }

  vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
    group = lib.group,
    callback = events.trigger.replace,
  })

  vim.api.nvim_create_autocmd({ "CompleteChanged" }, {
    group = lib.group,
    callback = function()
      events.pum.replace { kind = "changed", item = vim.v.event.completed_item }
    end,
  })

  vim.api.nvim_create_autocmd({ "CompleteDone" }, {
    group = lib.group,
    callback = function()
      events.pum.replace { kind = "clear" }
      events.done.replace(vim.v.completed_item)
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave" }, {
    group = lib.group,
    callback = function()
      events.pum.replace { kind = "clear" }
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = lib.group,
    callback = events.idle.replace,
  })

  return events
end

return M
