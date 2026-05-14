local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(capacity)
  capacity = capacity or math.huge

  local queue = {}
  local pull_waiter = nil
  local push_waiters = {}
  local closed = false

  local notify_pull = function()
    local f = pull_waiter
    pull_waiter = nil
    if f then
      f.resolve()
    end
  end

  local notify_push = function()
    local f = table.remove(push_waiters, 1)
    if f then
      f.resolve()
    end
  end

  local chan = {}

  chan.close = function()
    if closed then
      return
    end
    closed = true

    notify_pull()
    local snapshot = push_waiters
    push_waiters = {}
    for _, f in pairs(snapshot) do
      f.resolve()
    end
  end

  chan.pull = function()
    while #queue == 0 do
      if closed or runtime.cancelled() then
        return nil
      end
      pull_waiter = runtime.future()
      pull_waiter.await()
    end

    local pkt = table.remove(queue, 1)
    notify_push()
    return unpack(pkt, 1, pkt.n)
  end

  chan.push = function(...)
    while not closed and not runtime.cancelled() and #queue >= capacity do
      local f = runtime.future()
      table.insert(push_waiters, f)
      f.await()

      if runtime.cancelled() then
        for i, w in pairs(push_waiters) do
          if w == f then
            table.remove(push_waiters, i)
            break
          end
        end
      end
    end

    if closed or runtime.cancelled() then
      return
    end
    table.insert(queue, { n = select("#", ...), ... })
    notify_pull()
  end

  return setmetatable(chan, { __call = chan.pull })
end

return M
