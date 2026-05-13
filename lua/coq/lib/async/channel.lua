local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.mpsc = function()
  local q = queue.new()
  local waiter = nil
  return {
    push = function(item)
      if waiter then
        local r = waiter
        waiter = nil
        r(item)
      else
        q.push(item)
      end
    end,
    pull = function(h)
      if #q > 0 then
        return q.pop()
      end
      local resolve, await = runtime.future(h)
      waiter = resolve
      return await()
    end,
  }
end

return M
