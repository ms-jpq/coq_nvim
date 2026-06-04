local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async._runtime"

---@class async.Nursery
---@field closed boolean
---@field cancel fun()
---@field on_cancel fun(watcher: fun()): fun()
---@field spawn fun(fn: fun(defer: fun(cleanup: fun()))): async.Handle
---@field join fun()

local M = {}

---@return async.Nursery
M.new = function()
  local errors = {}
  local pending = lib.weak()
  local waiters = {}

  local h = handle.new(runtime.current())
  ---@diagnostic disable-next-line: missing-fields
  local nursery = {} ---@type async.Nursery

  nursery.closed = false
  nursery.cancel = h.cancel
  nursery.on_cancel = h.on_cancel

  nursery.join = function()
    if next(pending) ~= nil then
      local f = runtime.future()
      table.insert(waiters, f)
      f.await()
      runtime.check_cancellation()
    end
    nursery.closed = true
    h.cancel()
    errs.raise(errors)
  end

  nursery.spawn = function(fn)
    assert(not nursery.closed, "spawn: nursery is closed")
    local child = handle.new(h)

    runtime._detach(child, function()
      local thread = coroutine.running()
      pending[thread] = true

      local ok, err = pcall(lib.scope, function(defer)
        runtime.sleep(0)
        return fn(defer)
      end)
      pending[thread] = nil

      if not ok and not cancel.is(err) then
        table.insert(errors, err)
        h.cancel()
      end

      if next(pending) == nil then
        local acc = waiters
        waiters = {}
        for _, f in ipairs(acc) do
          f.resolve()
        end
      end
    end)

    return child
  end

  return nursery
end

return M
