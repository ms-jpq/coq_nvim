local async = require "coq.lib.async"
local context = require "coq.lib.context"
local events_m = require "coq.completions.events"

---@class idle.Ctx
---@field ctx ctx.full
---@field updated table<integer, true>
---@field removed table<integer, true>

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param sup producers.Supervisor<idle.Ctx>
---@param events completions.Events
M.bind = function(n, settings, sup, events)
  events.idle.replace {}
  events_m.subscribe_latest(n, events.idle, function()
    async.sleep(math.floor(settings.limits.idle_timeout * 1000))

    local diff = events.drain_bufs()
    sup.idle {
      ctx = context.full(),
      updated = diff.updated,
      removed = diff.removed,
    }
  end)
end

return M
