local closable = require "coq.lib.closable"
local queue = require "coq.lib.queue"
local util = require "coq.lib.channels.util"

---@class channels.Mpmc<T>: lib.Closable
---@field push fun(...: T): boolean
---@field pull fun(): T ...

local M = {}

---@generic T
---@param capacity number
---@return channels.Mpmc<T>
M.new = function(capacity)
  local que = queue.new()
  local readable = util.cond()
  local writable = util.cond()

  local state = closable.new(function()
    readable.wake()
    writable.wake()
  end)

  local chan = { close = state.close }

  chan.push = function(...)
    while not state.closed and que.len() >= capacity do
      writable.wait()
    end
    if state.closed then
      return false
    end

    que.push(util.pack(...))
    readable.wake()
    return true
  end

  chan.pull = function()
    while not state.closed and que.len() == 0 do
      readable.wait()
    end
    if que.len() == 0 then
      return nil
    end

    local packet = que.pop()
    ---@cast packet -nil
    writable.wake()
    return util.unpack(packet)
  end

  return chan
end

return M
