local mpsc = require "coq.lib.channels.mpsc"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.all = function(fns)
  local results = {}
  nursery.scope(function(n)
    for idx, fn in pairs(fns) do
      n.spawn(function()
        results[idx] = fn()
      end)
    end
  end)
  return results
end

M.race = function(fns)
  if #fns == 0 then
    return
  end

  local f = runtime.future()

  return nursery.scope(function(n, defer)
    defer(n.handle.on_cancel(f.resolve))

    for idx, fn in pairs(fns) do
      n.spawn(function()
        f.resolve(idx, fn())
      end)
    end

    local rets = { f.await(n.handle) }
    n.handle.cancel()
    return unpack(rets)
  end)
end

M.merge = function(iters)
  local chan = mpsc.new()
  local n = nursery.new()
  local active = #iters

  n.handle.on_cancel(chan.close)
  if active == 0 then
    n.handle.cancel()
  end

  for idx, iter in pairs(iters) do
    local p_iter = runtime.preemptible(iter)

    n.spawn(function()
      for v in p_iter do
        chan.push(idx, v)
      end

      active = active - 1
      if active == 0 then
        chan.close()
      end
    end)
  end

  return chan.pull
end

return M
