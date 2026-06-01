local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class async.Nursery
---@field handle async.Handle
---@field closed boolean
---@field spawn fun(fn: fun(defer: fun(cleanup: fun()))): async.Handle
---@field join fun()

local M = {}

---@return async.Nursery
M.new = function()
  local errors = {}
  local pending = setmetatable({}, { __mode = "k" })
  local waiters = {}

  local nursery = { handle = handle.new(runtime.current()), closed = false }

  nursery.join = function()
    if next(pending) ~= nil then
      local f = runtime.future()
      table.insert(waiters, f)
      f.await()
    end

    nursery.closed = true
    nursery.handle.cancel()
    errs.raise(errors)
  end

  nursery.spawn = function(fn)
    assert(not nursery.closed, "spawn: nursery is closed")
    local h = handle.new(nursery.handle)

    runtime.detach(h, function()
      local thread = coroutine.running()
      pending[thread] = true

      local ok, err = pcall(lib.scope, fn)
      pending[thread] = nil

      if not ok and not cancel.is(err) then
        table.insert(errors, err)
        nursery.handle.cancel()
      end

      if next(pending) == nil then
        local acc = waiters
        waiters = {}
        for _, f in ipairs(acc) do
          f.resolve()
        end
      end
    end)

    return h
  end

  ---@cast nursery async.Nursery
  return nursery
end

return M
