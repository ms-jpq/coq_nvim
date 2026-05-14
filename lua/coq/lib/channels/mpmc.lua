local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(capacity)
  capacity = capacity or math.huge

  local queue = {}
  local pull_waiters = {}
  local push_waiters = {}
  local closed = false

  local notify = function(waiters)
    local f = table.remove(waiters, 1)
    if f then
      f.resolve()
    end
  end

  local wait = function(waiters)
    local f = runtime.future()
    table.insert(waiters, f)
    f.await(runtime.current())

    if runtime.cancelled() then
      for i, w in pairs(waiters) do
        if w == f then
          table.remove(waiters, i)
          break
        end
      end
    end
  end

  local chan = {}

  chan.push = function(...)
    while not closed and not runtime.cancelled() and #queue >= capacity do
      wait(push_waiters)
    end

    if closed or runtime.cancelled() then
      return
    end
    table.insert(queue, { n = select("#", ...), ... })
    notify(pull_waiters)
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
    pull_waiters, push_waiters = {}, {}
    for _, f in pairs(pull_snap) do
      f.resolve()
    end
    for _, f in pairs(push_snap) do
      f.resolve()
    end
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
