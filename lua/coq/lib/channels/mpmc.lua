local runtime = require "coq.lib.async.runtime"
local sparse = require "coq.lib.sparse_table"

local M = {}

M.new = function(capacity)
  capacity = capacity or math.huge

  local queue = {}
  local pull_waiters = sparse.new()
  local push_waiters = sparse.new()
  local closed = false

  local notify = function(waiters)
    local f = waiters.take_first()
    if f then
      f.resolve()
    end
  end

  local wait = function(waiters)
    local f = runtime.future()
    local key = waiters.push(f)
    f.await(runtime.current())

    if runtime.cancelled() then
      waiters.remove(key)
    end
  end

  local chan = {}

  chan.push = function(...)
    while not closed and not runtime.cancelled() and #queue >= capacity do
      wait(push_waiters)
    end

    if closed or runtime.cancelled() then
      return false
    end
    table.insert(queue, { n = select("#", ...), ... })
    notify(pull_waiters)
    return true
  end

  chan.pull = function()
    while #queue == 0 do
      if closed or runtime.cancelled() then
        return nil
      end
      wait(pull_waiters)
    end

    local pkt = table.remove(queue, 1)
    notify(push_waiters)
    return unpack(pkt, 1, pkt.n)
  end

  chan.close = function()
    if closed then
      return
    end
    closed = true

    local pull_snap, push_snap = pull_waiters, push_waiters
    pull_waiters = sparse.new()
    push_waiters = sparse.new()
    for _, f in pull_snap.iter() do
      f.resolve()
    end
    for _, f in push_snap.iter() do
      f.resolve()
    end
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
