local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"
local util = require "coq.lib.channels.util"

local M = {}

M.new = function(capacity, h)
  capacity = math.max(1, capacity or math.huge)

  local queue = {}
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

  local state = util.closable(h, function()
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
    while not state.closed and #queue >= capacity do
      wait(push_waiters)
    end

    if state.closed then
      return false
    end

    table.insert(queue, util.pack(...))
    notify(pull_waiters)
    return true
  end

  chan.pull = function()
    while not state.closed and #queue == 0 do
      wait(pull_waiters)
    end

    if #queue == 0 then
      return nil
    end

    local packet = table.remove(queue, 1)
    notify(push_waiters)
    return util.unpack(packet)
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
