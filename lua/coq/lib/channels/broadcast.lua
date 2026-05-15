local async = require "coq.lib.async"
local sparse = require "coq.lib.sparse_table"

local M = {}

M.new = function(h)
  local subscribers = sparse.new()
  local closed = false

  local close_sub = function(sub)
    if sub.closed then
      return
    end
    sub.closed = true

    local f = sub.waiter
    sub.waiter = nil
    if f then
      f.resolve(nil)
    end
  end

  local chan = {}

  local unwatch_h
  chan.close = function()
    if closed then
      return
    end
    closed = true

    if unwatch_h then
      unwatch_h()
    end

    local snapshot = subscribers
    subscribers = sparse.new()
    for _, sub in snapshot.iter() do
      close_sub(sub)
    end
  end

  if h then
    unwatch_h = h.on_cancel(chan.close)
  end

  chan.replace = function(item)
    if closed then
      return
    end
    for _, sub in subscribers.iter() do
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
    local sub = { pending = nil, waiter = nil, closed = closed }
    local key
    if not closed then
      key = subscribers.push(sub)
    end

    local it = {}
    it.close = function()
      if sub.closed then
        return
      end
      if key then
        subscribers.remove(key)
      end
      close_sub(sub)
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
      return f.await()
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
