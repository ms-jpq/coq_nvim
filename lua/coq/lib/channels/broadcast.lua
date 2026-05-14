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
    local sub = { pending = nil, waiter = nil, closed = false }
    table.insert(subscribers, sub)

    local it = {}
    it.close = function()
      if sub.closed then
        return
      end
      sub.closed = true
      for i, s in ipairs(subscribers) do
        if s == sub then
          table.remove(subscribers, i)
          break
        end
      end
      if sub.waiter then
        local r = sub.waiter
        sub.waiter = nil
        r(nil)
      end
    end

    local next = function()
      if sub.closed then
        return nil
      end
      if sub.pending ~= nil then
        local v = sub.pending
        sub.pending = nil
        return v
      end

      local f = async.future()
      sub.waiter = f.resolve
      return f.await()
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
