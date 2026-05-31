local context = require "coq.lib.context"

local M = {}

---@param n async.Nursery
---@param sup producers.Producer
---@param idle channels.Broadcast<nil>
M.bind = function(n, sup, idle)
  n.spawn(function(defer)
    local iter = idle.subscribe()
    defer(iter.close)

    idle.replace {}
    for _ in iter do
      n.spawn(function()
        sup.idle(context.full())
      end)
    end
  end)
end

return M
