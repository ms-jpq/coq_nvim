local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local mpsc = require "coq.lib.channels.mpsc"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.all = function(fns)
  local results = {}
  local n = nursery.new()
  for idx, fn in ipairs(fns) do
    n.spawn(function()
      results[idx] = fn()
    end)
  end
  n.join()
  return results
end

M.race = function(fns)
  if #fns == 0 then
    return
  end

  local f = runtime.future()
  local n = nursery.new()

  return lib.scope(function(defer)
    defer(n.handle.cancel)
    defer(n.handle.on_cancel(f.resolve))

    for idx, fn in ipairs(fns) do
      n.spawn(function()
        f.resolve(idx, fn())
      end)
    end

    local ret = { f.await(n.handle) }
    n.handle.cancel()
    n.join()
    return unpack(ret)
  end)
end

M.preemptible = function(iter)
  return function()
    local current = runtime.current()
    if current.cancelled then
      return nil
    end

    local h = handle.new(current)
    local f = runtime.future()
    local err
    local unwatch = h.on_cancel(f.resolve)

    local thread = coroutine.create(function()
      local ok, ret = xpcall(iter, debug.traceback)
      if ok then
        f.resolve(ret)
      else
        err = ret
        f.resolve()
      end
    end)
    runtime.bind(thread, h)
    coroutine.resume(thread)

    local v = lib.scope(function(defer)
      defer(h.cancel)
      defer(unwatch)
      return f.await(h)
    end)

    if err then
      error(err, 0)
    end
    return v
  end
end

M.merge = function(fns)
  local chan = mpsc.new()
  local n = nursery.new()
  local active = #fns

  n.handle.on_cancel(chan.close)
  if active == 0 then
    n.handle.cancel()
  end

  for idx, fn in pairs(fns) do
    local fn_p = M.preemptible(fn)

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
