local errs = require "coq.lib.errs"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.new = function(parent)
  parent = parent or runtime.current()
  local nursery = { handle = handle.new(parent), errors = {} }
  local pending = setmetatable({}, { __mode = "k" })
  local empty_waiters = {}
  local closed = false

  nursery.close = function()
    closed = true
  end

  nursery.spawn = function(fn)
    assert(not closed, "spawn: nursery is closed")

    local thread
    thread = coroutine.create(function()
      local ok, err = xpcall(fn, debug.traceback)
      xpcall(function()
        pending[thread] = nil
        if not ok then
          table.insert(nursery.errors, err)
          nursery.handle.cancel()
        end

        if next(pending) == nil then
          local waiters = empty_waiters
          empty_waiters = {}
          for _, cb in ipairs(waiters) do
            cb()
          end
        end
      end, function(e)
        vim.notify(e, vim.log.levels.ERROR)
      end)
    end)

    pending[thread] = true
    runtime.bind(thread, nursery.handle)
    coroutine.resume(thread)
  end

  nursery.join = function()
    assert(coroutine.running() ~= nil, "join: must be called inside a coroutine")
    if next(pending) ~= nil then
      local f = runtime.future()
      table.insert(empty_waiters, f.resolve)
      f.await()
    end
    local errors = nursery.errors
    nursery.errors = {}
    errs.raise(errors)
  end

  return nursery
end

M.scope = function(parent, body)
  if body == nil then
    body = parent
    parent = nil
  end

  local nursery = M.new(parent)
  lib.scope(function(defer)
    defer(nursery.close)
    defer(nursery.handle.cancel)
    nursery.spawn(function()
      body(nursery)
    end)
    nursery.join()
  end)
end

return M
