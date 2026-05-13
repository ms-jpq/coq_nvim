local async = require "coq.lib.async"

local M = {}

M.new = function()
  local chan = {}
  local subscribers = {}

  chan.replace = function(item)
    for _, sub in pairs(subscribers) do
      if sub.waiter then
        local r = sub.waiter
        sub.waiter = nil
        r(item)
      else
        sub.pending = item
      end
    end
  end

  chan.subscribe = function()
    local h = async.current()
    local sub = { pending = nil, waiter = nil }
    table.insert(subscribers, sub)

    h.watch(function()
      for i, s in ipairs(subscribers) do
        if s == sub then
          table.remove(subscribers, i)
          break
        end
      end
    end)

    return function()
      if sub.pending ~= nil then
        local v = sub.pending
        sub.pending = nil
        return v
      end

      local f = async.future()
      sub.waiter = f.resolve
      return f.await()
    end
  end

  return chan
end

return M
