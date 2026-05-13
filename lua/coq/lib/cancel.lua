local lib = require "coq.lib"

local M = {}

M.token = function(parent)
  local watchers = {}
  local token = { cancelled = false }

  local fire = function(watcher)
    if type(watcher) == "function" then
      watcher()
    else
      watcher.cancel()
    end
  end

  token.cancel = function()
    lib.scope(function(defer)
      defer(function()
        watchers = {}
      end)

      if token.cancelled then
        return
      end
      token.cancelled = true
      for _, watcher in pairs(watchers) do
        fire(watcher)
      end
    end)
  end

  token.watch = function(watcher)
    if token.cancelled then
      fire(watcher)
    else
      table.insert(watchers, watcher)
    end
  end

  if parent then
    parent.watch(token)
    if parent.cancelled then
      token.cancel()
    end
  end

  return token
end

M.ROOT = M.token()

return M
