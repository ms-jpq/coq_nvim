local async = require "coq.lib.async"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function()
  local chan = {}
  local subscribers = {}

  chan.replace = function(item)
    for _, sub in pairs(subscribers) do
      local f = sub.waiter
      sub.waiter = nil

      if f then
        f.resolve(item)
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

      local f = sub.waiter
      sub.waiter = nil
      if f then
        f.resolve(nil)
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
      sub.waiter = f
      return f.await(runtime.current())
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
