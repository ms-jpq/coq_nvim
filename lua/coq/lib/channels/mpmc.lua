local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"

local M = {}

M.new = function(capacity, h)
  capacity = math.max(1, capacity or math.huge)

  local queue = {}
  local pull_waiters = sparse.new()
  local push_waiters = sparse.new()
  local closed = false

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

    local push_snap, pull_snap = push_waiters, pull_waiters
    push_waiters, pull_waiters = sparse.new(), sparse.new()

    for _, f in pull_snap.iter() do
      f.resolve()
    end
    for _, f in push_snap.iter() do
      f.resolve()
    end
  end

  if h then
    unwatch_h = h.on_cancel(chan.close)
  end

  chan.push = function(...)
    while not closed and #queue >= capacity do
      wait(push_waiters)
    end

    if closed then
      return false
    end

    table.insert(queue, { n = select("#", ...), ... })
    notify(pull_waiters)
    return true
  end

  chan.pull = function()
    while not closed and #queue == 0 do
      wait(pull_waiters)
    end

    if #queue == 0 then
      return nil
    end

    local packet = table.remove(queue, 1)
    notify(push_waiters)
    return unpack(packet, 1, packet.n)
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
