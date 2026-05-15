local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"
local util = require "coq.lib.channels.util"

local M = {}

M.new = function(h)
  local subscribers = sparse.new()

  local dismiss = function(sub)
    if sub.gone then
      return
    end
    sub.gone = true

    local f = sub.waiter
    sub.waiter = nil
    if f then
      f.resolve(nil)
    end
  end

  local state = util.closable(h, function()
    local snapshot = subscribers
    subscribers = sparse.new()
    for _, sub in snapshot.iter() do
      dismiss(sub)
    end
  end)

  local chan = {}
  chan.close = state.close

  chan.replace = function(...)
    if state.closed then
      return false
    end
    local packet = util.pack(...)
    for _, sub in subscribers.iter() do
      local f = sub.waiter
      sub.waiter = nil

      if f then
        f.resolve(packet)
      else
        sub.pending = packet
      end
    end
    return true
  end

  chan.subscribe = function()
    local sub = { pending = nil, waiter = nil, gone = state.closed }
    local key
    if not state.closed then
      key = subscribers.push(sub)
    end

    local it = {}
    it.close = function()
      if sub.gone then
        return
      end
      if key then
        subscribers.remove(key)
      end
      dismiss(sub)
    end

    local next = function()
      local packet
      if sub.pending ~= nil then
        packet = sub.pending
        sub.pending = nil
      elseif sub.gone then
        return nil
      else
        local f = runtime.future()
        sub.waiter = f
        packet = f.await()
        if packet == nil then
          return nil
        end
      end
      return util.unpack(packet)
    end

    return setmetatable(it, { __call = next })
  end

  return chan
end

return M
