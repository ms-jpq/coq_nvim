local cancel = require "coq.lib.async.cancel"
local closable = require "coq.lib.closable"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async._runtime"

---@class async.Nursery: lib.ClosableState
---@field cancel fun()
---@field on_cancel fun(watcher: fun()): fun()
---@field spawn fun(fn: fun(defer: fun(cleanup: fun()))): async.Handle
---@field join fun()

local M = {}

---@return async.Nursery
M.new = function()
  local errors = {}
  local active = 0
  local waiters = {}

  local h = handle.new(runtime.current())

  local state = closable.new(h.cancel)

  ---@diagnostic disable-next-line: missing-fields
  local nursery = {} ---@type async.Nursery

  nursery.cancel = state.close
  nursery.on_cancel = h.on_cancel

  nursery.join = function()
    lib.scope(function(defer)
      defer(state.close)

      if active > 0 then
        errs.check_raise(errors)
        local f = runtime.future()
        table.insert(waiters, f)
        f.await()
      end

      errs.check_raise(errors)
      runtime.check_cancel()
    end)
  end

  nursery.spawn = function(fn)
    assert(not state.closed, "spawn: nursery is closed")
    local child = handle.new(h)
    active = active + 1

    runtime._detach(child, function()
      local ok, err = pcall(lib.scope, function(defer)
        runtime.sleep(0)
        return fn(defer)
      end)
      active = active - 1

      if not ok and not cancel.is(err) then
        table.insert(errors, err)
        h.cancel()
      end

      if active == 0 then
        local acc = waiters
        waiters = {}
        for _, f in pairs(acc) do
          f.resolve()
        end
      end
    end)

    return child
  end

  setmetatable(nursery, { __index = state })
  return nursery
end

return M
