local context = require "coq.lib.context"
local insertion = require "coq.completions.insertion"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param ranker index.Ranker
---@param sup producers.Producer
---@param trigger channels.Broadcast<nil>
M.bind = function(n, settings, ranker, sup, trigger)
  n.spawn(function(defer)
    local iter = trigger.subscribe()
    defer(iter.close)

    for _ in iter do
      n.spawn(function()
        local ctx = context.full()
        insertion.complete(ctx, settings, ranker, sup.search(ctx))
      end)
    end
  end)
end

return M
