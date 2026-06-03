local async = require "coq.lib.async"
local context = require "coq.lib.context"
local events_m = require "coq.completions.events"

---@class idle.Ctx
---@field ctx ctx.full
---@field cache_dir string
---@field updated table<integer, true>
---@field removed table<integer, true>

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param sup producers.Producer<idle.Ctx>
---@param events completions.Events
M.bind = function(n, settings, sup, events)
  events.idle.replace {}

  local carry = { updated = {}, removed = {} }

  events_m.subscribe_latest(n, events.idle, function()
    async.sleep(math.floor(settings.limits.idle_timeout * 1000))

    local diff = events.drain_bufs()
    for buf in pairs(diff.removed) do
      carry.updated[buf] = nil
      carry.removed[buf] = true
    end
    for buf in pairs(diff.updated) do
      carry.removed[buf] = nil
      carry.updated[buf] = true
    end

    sup.idle(settings, {
      ctx = context.full(),
      cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "coq"),
      updated = carry.updated,
      removed = carry.removed,
    })

    carry = { updated = {}, removed = {} }
  end)
end

return M
