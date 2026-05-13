local lib = require "coq.lib"

local M = {}

local pending = setmetatable({}, { __mode = "k" })
local empty_waiters = setmetatable({}, { __mode = "k" })

M.new = function(parent)
  local watchers = {}
  local handle = { cancelled = false }
  local unwatch_from_parent

  local fire = function(watcher)
    if type(watcher) == "function" then
      watcher()
    else
      watcher.cancel()
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

M.register = function(h, thread)
  local set = pending[h]
  if not set then
    set = setmetatable({}, { __mode = "k" })
    pending[h] = set
  end
  set[thread] = true
end

M.deregister = function(h, thread)
  local set = pending[h]
  if not set then
    return
  end
  set[thread] = nil
  if next(set) == nil then
    local waiters = empty_waiters[h]
    if waiters then
      empty_waiters[h] = nil
      for _, cb in ipairs(waiters) do
        cb()
      end
    end
  end
end

M.on_empty = function(h, cb)
  local set = pending[h]
  if not set or next(set) == nil then
    cb()
    return
  end
  local waiters = empty_waiters[h]
  if not waiters then
    waiters = {}
    empty_waiters[h] = waiters
  end
  table.insert(waiters, cb)
end

M.ROOT = M.new()

return M
