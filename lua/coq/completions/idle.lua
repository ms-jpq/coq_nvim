local async = require "coq.lib.async"
local context = require "coq.lib.context"
local events = require "coq.completions.events"

local M = {}

---@param n async.Nursery
---@param sup producers.Producer<ctx.full>
---@param idle channels.Broadcast<nil>
M.bind = function(n, sup, idle)
  idle.replace {}
  events.subscribe_latest(n, idle, function()
    async.sleep(-1)
    sup.idle(context.full())
  end)
end

return M
