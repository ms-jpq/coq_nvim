local async = require "coq.lib.async"
local context = require "coq.lib.context"
local events_m = require "coq.completions.events"

---@class idle.Ctx
---@field ctx ctx.full
---@field updated table<integer, true>
---@field removed table<integer, true>

local M = {}

---@param n async.Nursery
---@param sup producers.Supervisor<idle.Ctx>
---@param events completions.Events
M.bind = function(n, sup, events)
  events.idle.replace {}
  events_m.subscribe_latest(n, events.idle, function()
    async.sleep(-1)

    local diff = events.drain_bufs()
    sup.idle {
      ctx = context.full(),
      updated = diff.updated,
      removed = diff.removed,
    }
  end)
end

return M
