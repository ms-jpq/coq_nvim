local async = require "coq.lib.async"
local context = require "coq.lib.context"

local M = {}

---@param n async.Nursery
---@param sup producers.Producer<ctx.full>
---@param idle channels.Broadcast<nil>
M.bind = function(n, sup, idle)
  n.spawn(function(defer)
    local iter = idle.subscribe()
    defer(iter.close)

    idle.replace {}
    ---@type async.Handle?
    local prev = nil
    for _ in iter do
      if prev then
        prev.cancel()
      end
      prev = n.spawn(function()
        async.sleep(-1)
        sup.idle(context.full())
      end)
    end
  end)
end

return M
