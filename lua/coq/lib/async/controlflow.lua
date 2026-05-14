local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
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
  local ret = {}

  nursery.scope(function(n, defer)
    defer(n.handle.on_cancel(f.resolve))
    defer(n.handle.cancel)

    for idx, fn in ipairs(fns) do
      n.spawn(function()
        f.resolve(idx, fn())
      end)
    end

    ret = { f.await(n.handle) }
  end)

  return unpack(ret)
end

M.preemptible = function(iter)
  return function()
    if runtime.cancelled() then
      return nil
    end

    local f = runtime.future()
    local h = handle.new(runtime.current())
    h.on_cancel(f.resolve)

    local thread = coroutine.create(function()
      f.resolve(xpcall(iter, debug.traceback))
    end)
    runtime.bind(thread, h)
    coroutine.resume(thread)

    local ok, ret = lib.scope(function(defer)
      defer(h.cancel)
      return f.await(h)
    end)

    if ok == nil then
      return nil
    end
    if not ok then
      error(ret, 0)
    end
    return ret
  end
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
    local fn_p = M.preemptible(iter)

    n.spawn(function()
      for v in fn_p do
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
