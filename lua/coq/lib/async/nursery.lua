local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(parent)
  parent = parent or runtime.current()
  local cs = handle.new(parent)
  local pending = setmetatable({}, { __mode = "k" })
  local empty_waiters = {}

  local n = {
    cancel = cs,
    error = nil,
  }

  n.spawn = function(fn)
    local thread
    thread = coroutine.create(function()
      local ok, err = xpcall(fn, debug.traceback)
      pending[thread] = nil
      if not ok and not n.error then
        n.error = err
        cs.cancel()
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
    runtime.bind(thread, cs)
    coroutine.resume(thread)
  end

  n.join = function()
    if next(pending) ~= nil then
      local resolve, await = runtime.future()
      table.insert(empty_waiters, resolve)
      await()
    end
    if n.error then
      local err = n.error
      n.error = nil
      error(err, 0)
    end
  end

  return n
end

M.scope = function(body, parent)
  local n = M.new(parent)
  local ok, err = pcall(body, n)
  if not ok then
    if not n.error then
      n.error = err
    end
    n.cancel.cancel()
  end
  n.join()
end

return M
