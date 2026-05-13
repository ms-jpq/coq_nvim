local lib = require "coq.lib"

local M = {}

M.token = function(parent)
  local watchers = {}
  local token = { cancelled = false }
  local unwatch_from_parent

  local fire = function(watcher)
    if type(watcher) == "function" then
      watcher()
    else
      watcher.cancel()
    end
  end

  token.cancel = function()
    lib.scope(function(defer)
      if token.cancelled then
        return
      end
      token.cancelled = true
      defer(function()
        if unwatch_from_parent then
          unwatch_from_parent()
        end
      end)

      local pending = watchers
      watchers = {}
      for _, watcher in pairs(pending) do
        fire(watcher)
      end
    end)
  end

  token.watch = function(watcher)
    if token.cancelled then
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
    unwatch_from_parent = parent.watch(token)
    if parent.cancelled then
      token.cancel()
    end
  end

  return token
end

M.ROOT = M.token()

return M
