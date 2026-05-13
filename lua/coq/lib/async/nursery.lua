local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(parent)
  parent = parent or runtime.current()
  local nursery = { handle = handle.new(parent), error = nil }

  local pending = setmetatable({}, { __mode = "k" })
  local empty_waiters = {}

  nursery.spawn = function(fn)
    local thread
    thread = coroutine.create(function()
      local ok, err = xpcall(fn, debug.traceback)
      pending[thread] = nil
      if not ok and not nursery.error then
        nursery.error = err
        nursery.handle.cancel()
      end
      if next(pending) == nil then
        local waiters = empty_waiters
        empty_waiters = {}
        for _, cb in ipairs(waiters) do
          cb()
        end
      end
    end)

    pending[thread] = true
    runtime.bind(thread, nursery.handle)
    coroutine.resume(thread)
  end

  nursery.join = function()
    if next(pending) ~= nil then
      local resolve, await = runtime.future()
      table.insert(empty_waiters, resolve)
      await()
    end
    if nursery.error then
      local err = nursery.error
      nursery.error = nil
      error(err, 0)
    end
  end

  return nursery
end

M.scope = function(parent, body)
  if body == nil then
    body = parent
    parent = nil
  end

  local nursery = M.new(parent)
  local ok, err = pcall(body, nursery)
  if not ok then
    if not nursery.error then
      nursery.error = err
    end
    nursery.handle.cancel()
  end
  nursery.join()
end

return M
