local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class async.Nursery
---@field handle async.Handle
---@field closed boolean
---@field spawn fun(fn: fun(defer: fun(cleanup: fun())))
---@field join fun()

local M = {}

---@param parent? async.Handle
---@return async.Nursery
M.new = function(parent)
  parent = parent or runtime.current()
  local errors = {}
  local pending = setmetatable({}, { __mode = "k" })
  local waiters = {}

  local nursery = { handle = handle.new(parent), closed = false }

  nursery.spawn = function(fn)
    assert(not nursery.closed, "spawn: nursery is closed")

    runtime.detach(nursery.handle, function()
      pending[coroutine.running()] = true
      runtime.sleep(0)
      local ok, err = pcall(lib.scope, fn)
      pending[coroutine.running()] = nil

      if not ok then
        lib.report(err)
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
  end

  nursery.join = function()
    assert(coroutine.running() ~= nil, "join: must be called inside a coroutine")

    if next(pending) ~= nil then
      local f = runtime.future()
      table.insert(waiters, f)
      f.await(runtime.current())
    end

    nursery.closed = true
    nursery.handle.cancel()
    errs.raise(errors)
  end

  ---@cast nursery async.Nursery
  return nursery
end

return M
