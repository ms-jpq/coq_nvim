local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(parent)
  parent = parent or runtime.current()
  local nursery = { handle = handle.new(parent), errors = {}, closed = false }
  local pending = setmetatable({}, { __mode = "k" })
  local waiters = {}

  nursery.close = function()
    nursery.closed = true
  end

  nursery.spawn = function(fn)
    assert(not nursery.closed, "spawn: nursery is closed")

    local thread = coroutine.create(function()
      runtime.sleep(0)
      local ok, err = xpcall(lib.scope, debug.traceback, fn)
      pending[coroutine.running()] = nil

      if not ok then
        table.insert(nursery.errors, err)
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

    pending[thread] = true
    runtime.bind(thread, nursery.handle)
    coroutine.resume(thread)
  end

  nursery.join = function()
    assert(coroutine.running() ~= nil, "join: must be called inside a coroutine")

    if next(pending) ~= nil then
      local f = runtime.future()
      table.insert(waiters, f)
      f.await(runtime.current())
    end

    errs.raise(nursery.errors)
  end

  return nursery
end

M.scope = function(parent, body)
  if body == nil then
    body = parent
    parent = nil
  end

  local nursery = M.new(parent)
  return lib.scope(function(defer)
    defer(nursery.close)
    defer(nursery.handle.cancel)

    local rets = {}
    nursery.spawn(function()
      rets = { body(nursery, defer) }
    end)
    nursery.join()
    return unpack(rets)
  end)
end

return M
