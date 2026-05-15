local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
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
  local unwatch = function() end

  chan.close = function()
    if closed then
      return
    end
    closed = true
    unwatch()

    local snapshot = subscribers
    subscribers = sparse.new()
    for _, sub in snapshot.iter() do
      close_sub(sub)
    end
  end

  unwatch = handle.bind_close(h, chan.close)

  chan.replace = function(...)
    if closed then
      return false
    end
    local pkt = { n = select("#", ...), ... }
    for _, sub in subscribers.iter() do
      local f = sub.waiter
      sub.waiter = nil

      if f then
        f.resolve(pkt)
      else
        sub.pending = pkt
      end
    end
    return true
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
      local pkt
      if sub.pending ~= nil then
        pkt = sub.pending
        sub.pending = nil
      elseif sub.closed then
        return nil
      else
        local f = async.future()
        sub.waiter = f
        pkt = f.await()
        if pkt == nil then
          return nil
        end
      end
      return unpack(pkt, 1, pkt.n)
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
