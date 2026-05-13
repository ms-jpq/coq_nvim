local handle = require "coq.lib.async.handle"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = runtime

M.handle = handle.new
M.ROOT = handle.ROOT
M.channel = require "coq.lib.async.channel"
M.nursery = nursery.new
M.scope = nursery.scope

M.race = function(h, fns)
  if fns == nil then
    fns = h
    h = nil
  end
  h = h or handle.new(M.current())
  local resolve, await = M.future(h)
  local race_err

  h.watch(function()
    resolve()
  end)

  for idx, fn in ipairs(fns) do
    M.run(h, function()
      local ok, err = xpcall(function()
        resolve(idx, fn())
        h.cancel()
      end, debug.traceback)
      if not ok and not race_err then
        race_err = err
        h.cancel()
      end
    end)
  end

  local ret = { await() }
  if race_err then
    error(race_err, 0)
  end
  return unpack(ret)
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
