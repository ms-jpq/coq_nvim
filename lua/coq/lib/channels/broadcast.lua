local async = require "coq.lib.async"

local M = {}

M.new = function()
  local subscribers = {}
  local chan = {}

  chan.push = function(item)
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

    if h then
      h.watch(function()
        for i, s in ipairs(subscribers) do
          if s == sub then
            table.remove(subscribers, i)
            break
          end
        end
      end)
    end

    return function()
      if sub.pending ~= nil then
        local v = sub.pending
        sub.pending = nil
        return v
      end

      local resolve, await = async.future()
      sub.waiter = resolve
      return await()
    end
  end

  return chan
end

return M
