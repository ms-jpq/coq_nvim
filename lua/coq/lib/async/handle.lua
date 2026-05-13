local lib = require "coq.lib"

local M = {}

local fire = function(watcher)
  if type(watcher) == "function" then
    watcher()
  else
    watcher.cancel()
  end
end

M.new = function(parent, deadline_ms)
  local handle = { cancelled = false }
  local watchers = {}
  local unwatch_from_parent = function() end
  local timer

  handle.cancel = function()
    if handle.cancelled then
      return
    end
    handle.cancelled = true

    lib.scope(function(defer)
      defer(function()
        if timer and not timer:is_closing() then
          timer:stop()
          timer:close()
        end
      end)
      defer(unwatch_from_parent)

      local snapshot = watchers
      watchers = {}
      for _, w in ipairs(snapshot) do
        fire(w)
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
  end

  if deadline_ms then
    timer = vim.uv.new_timer()
    timer:start(deadline_ms, 0, handle.cancel)
  end

  return handle
end

return M
