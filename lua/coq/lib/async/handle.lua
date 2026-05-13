local lib = require "coq.lib"

local M = {}

M.new = function(parent, deadline_ms)
  local handle = { cancelled = false }

  local watchers = {}
  local unwatch_from_parent
  local timer

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
        if timer and not timer:is_closing() then
          timer:stop()
          timer:close()
        end
      end)

      local snapshot = watchers
      watchers = {}
      for _, watcher in ipairs(snapshot) do
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
      for i, w in ipairs(watchers) do
        if w == watcher then
          table.remove(watchers, i)
          return
        end
      end
    end
  end

  if deadline_ms then
    timer = vim.uv.new_timer()
    timer:start(deadline_ms, 0, handle.cancel)
  end

  if parent then
    unwatch_from_parent = parent.watch(handle)
    if parent.cancelled then
      handle.cancel()
    end
  end

  return handle
end

return M
