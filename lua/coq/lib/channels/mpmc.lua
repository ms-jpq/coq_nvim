local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"
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
  local pull_waiters = sparse.new()
  local push_waiters = sparse.new()

  local notify = function(waiters)
    local f = waiters.shift()
    if f then
      f.resolve()
    end
  end

  local wait = function(waiters)
    local f = runtime.future()
    waiters.push(f)
    f.await()
  end

  local state = util.closable(function()
    local push_snap, pull_snap = push_waiters, pull_waiters
    push_waiters, pull_waiters = sparse.new(), sparse.new()

    for _, f in pull_snap.iter() do
      f.resolve()
    end
    for _, f in push_snap.iter() do
      f.resolve()
    end
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
