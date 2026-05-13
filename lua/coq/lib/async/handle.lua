local lib = require "coq.lib"

local M = {}

M.new = function(parent)
  local watchers = {}
  local handle = { cancelled = false }
  local unwatch_from_parent
  local pending = setmetatable({}, { __mode = "k" })
  local empty_waiters = {}

  local fire = function(watcher)
    if type(watcher) == "function" then
      watcher()
    else
      watcher.cancel()
    end
  end

  handle.register = function(thread)
    pending[thread] = true
  end

  handle.deregister = function(thread)
    pending[thread] = nil
    if next(pending) == nil and #empty_waiters > 0 then
      local waiters = empty_waiters
      empty_waiters = {}
      for _, cb in ipairs(waiters) do
        cb()
      end
    end
  end

  handle.on_empty = function(cb)
    if next(pending) == nil then
      cb()
    else
      table.insert(empty_waiters, cb)
    end
  end

  handle.cancel = function()
    lib.scope(function(defer)
      if handle.cancelled then
        return
      end
      handle.cancelled = true
      defer(function()
        if unwatch_from_parent then
          unwatch_from_parent()
        end
      end)

      local snapshot = watchers
      watchers = {}
      for _, watcher in pairs(snapshot) do
        fire(watcher)
      end
    end)
  end

  handle.watch = function(watcher)
    if handle.cancelled then
      fire(watcher)
      return function() end
    end
    table.insert(watchers, watcher)
    return function()
      for i, w in pairs(watchers) do
        if w == watcher then
          table.remove(watchers, i)
          return
        end
      end
    end
  end

  if parent then
    unwatch_from_parent = parent.watch(handle)
    if parent.cancelled then
      handle.cancel()
    end
  end

  return handle
end

M.ROOT = M.new()

return M
