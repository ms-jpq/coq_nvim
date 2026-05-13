local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {
  current = runtime.current,
  cancelled = runtime.cancelled,
  checkpoint = runtime.checkpoint,
  future = runtime.future,
  wrap = runtime.wrap,
  thunk = runtime.thunk,
  sleep = runtime.sleep,
  nursery = nursery.new,
  scope = nursery.scope,
}

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

  local f = M.future()
  local n = nursery.new()
  n.handle.on_cancel(f.resolve)

  for idx, fn in ipairs(fns) do
    n.spawn(function()
      f.resolve(idx, fn())
    end)
  end

  local ret = { f.await(n.handle) }
  n.handle.cancel()
  n.join()

  return unpack(ret)
end

M.merge = function(fns)
  local iters = {}
  for idx, fn in ipairs(fns) do
    table.insert(iters, { idx = idx, fn = fn })
  end

  return function()
    while #iters > 0 do
      local race_fns = {}
      for _, entry in ipairs(iters) do
        table.insert(race_fns, entry.fn)
      end

      local winner, value = M.race(race_fns)

      if winner == nil then
        return nil
      end
      if value ~= nil then
        return iters[winner].idx, value
      end
      table.remove(iters, winner)
    end
  end
end

return M
