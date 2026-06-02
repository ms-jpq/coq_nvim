local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local insertion = require "coq.completions.insertion"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param ranker index.Ranker
---@param sup producers.Producer<ctx.full>
---@param trigger channels.Broadcast<nil>
M.bind = function(n, settings, ranker, sup, trigger)
  events.subscribe_latest(n, trigger, function()
    atools.scheduled()
    local ctx = context.full()
    local searched = sup.search(ctx)
    insertion.complete(ctx, settings, ranker, searched)
  end)
end

return M
