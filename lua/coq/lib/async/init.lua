local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

local M = runtime

M.handle = handle.new
M.ROOT = handle.ROOT
M.channel = require "coq.lib.async.channel"

M.race = function(opts)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local h = opts.handle or handle.new(M.current_handle())
  local resolved = nil

  local resume = function(values)
    if coroutine.status(thread) == "suspended" then
      local ok, msg = coroutine.resume(thread, unpack(values))
      if not ok then
        error(msg, 0)
      end
    end
  end

  local finish = function(idx)
    return function(...)
      if resolved then
        return
      end
      resolved = { idx, ... }
      h.cancel()
      resume(resolved)
    end
  end

  h.watch(function()
    if resolved then
      return
    end
    resolved = {}
    resume(resolved)
  end)

  for idx, fn in ipairs(opts) do
    local done = finish(idx)
    M.run(h, function()
      done(fn())
    end)
  end

  if resolved then
    return unpack(resolved)
  end
  return coroutine.yield()
end

M.merge = function(opts)
  local iters = {}
  for idx, fn in ipairs(opts) do
    table.insert(iters, { idx = idx, fn = fn })
  end
  local parent = opts.handle

  return function()
    while #iters > 0 do
      local race_opts = {}
      for i, entry in ipairs(iters) do
        race_opts[i] = function()
          return entry.fn()
        end
      end
      if parent then
        race_opts.handle = handle.new(parent)
      end

      local winner, value = M.race(race_opts)

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
