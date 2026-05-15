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
  local watchers, watchers_count = {}, 0
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

      local snapshot, count = watchers, watchers_count
      watchers, watchers_count = {}, 0

      for k = count, 1, -1 do
        local w = snapshot[k]
        if w then
          defer(function()
            fire(w)
          end)
        end
      end
    end)
  end

  handle.on_cancel = function(watcher)
    if handle.cancelled then
      fire(watcher)
      return function() end
    end

    watchers_count = watchers_count + 1
    local key = watchers_count

    watchers[key] = watcher
    return function()
      watchers[key] = nil
    end
  end

  if parent then
    unwatch_from_parent = parent.on_cancel(handle)
  end

  if deadline_ms then
    timer = vim.uv.new_timer()
    timer:start(deadline_ms, 0, handle.cancel)
  end

  return handle
end

return M
