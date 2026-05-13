-- Single-producer / single-consumer queue with an awaitable pull.

local async = require "coq.lib.async"

local M = {}

M.make = function()
  local queue, waiter = {}, nil
  return {
    push = function(item)
      if waiter then
        local r = waiter
        waiter = nil
        r(item)
      else
        table.insert(queue, item)
      end
    end,
    pull = function()
      if #queue > 0 then
        return table.remove(queue, 1)
      end
      local resolve, await = async.future()
      waiter = resolve
      return await()
    end,
  }
end

return M
