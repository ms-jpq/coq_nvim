local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"
local util = require "coq.lib.channels.util"

---@class channels.Mpmc<T>: lib.Closable
---@field push fun(...: T): boolean
---@field pull fun(): T ...
---@overload fun(): T ...

local M = {}

---@generic T
---@param capacity? integer
---@return channels.Mpmc<T>
M.new = function(capacity)
  capacity = math.max(1, capacity or math.huge)

  local que = queue.new()
  local pull_waiters = queue.new()
  local push_waiters = queue.new()

  local notify = function(waiters)
    local f = waiters.pop()
    if f then
      f.resolve()
    end
  end

  local wait = function(waiters)
    local f = runtime.future()
    waiters.push(f)
    f.await()
  end

  local drain = function(waiters)
    while true do
      local f = waiters.pop()
      if not f then
        return
      end
      f.resolve()
    end
  end

  local state = util.closable(function()
    drain(pull_waiters)
    drain(push_waiters)
  end)

  local chan = { close = state.close }

  chan.push = function(...)
    while not state.closed and que.len() >= capacity do
      wait(push_waiters)
    end

    if state.closed then
      return false
    end

    que.push(util.pack(...))
    notify(pull_waiters)
    return true
  end

  chan.pull = function()
    while not state.closed and que.len() == 0 do
      wait(pull_waiters)
    end

    if que.len() == 0 then
      return nil
    end

    local packet = que.pop()
    ---@cast packet -nil
    notify(push_waiters)
    return util.unpack(packet)
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
