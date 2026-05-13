local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {
  current = runtime.current,
  cancelled = runtime.cancelled,
  future = runtime.future,
  wrap = runtime.wrap,
  thunk = runtime.thunk,
  sleep = runtime.sleep,
  handle = handle.new,
  nursery = nursery.new,
  scope = nursery.scope,
}

M.race = function(h, fns)
  if fns == nil then
    fns = h
    h = nil
  end
  if #fns == 0 then
    return
  end

  h = h or handle.new(M.current())

  return lib.scope(function(defer)
    defer(h.cancel)

    local resolve, await = M.future()
    local race_err

    h.watch(function()
      resolve()
    end)

    for idx, fn in ipairs(fns) do
      local thread = coroutine.create(function()
        local ok, err = xpcall(function()
          resolve(idx, fn())
        end, debug.traceback)
        if not ok and not race_err then
          race_err = err
          h.cancel()
        end
      end)
      runtime.bind(thread, h)
      coroutine.resume(thread)
    end

    local ret = { await(h) }
    if race_err then
      error(race_err, 0)
    end
    return unpack(ret)
  end)
end

M.merge = function(parent, fns)
  if fns == nil then
    fns = parent
    parent = nil
  end
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
      local race_h
      if parent then
        race_h = handle.new(parent)
      end

      local winner, value = M.race(race_h, race_fns)

      if winner == nil then
        return nil
      end

      if value == nil then
        table.remove(iters, winner)
      else
        return iters[winner].idx, value
      end
    end
    return nil
  end
end

return M
