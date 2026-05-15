local lib = require "coq.lib"
local sparse = require "coq.lib.sparse_table"

local M = {}

local fire = function(watcher)
  if type(watcher) == "function" then
    watcher()
  else
    watcher.cancel()
  end
end

M.bind_close = function(h, close_fn)
  if not h then
    return function() end
  end
  return h.on_cancel(close_fn)
end

M.new = function(parent, deadline_ms)
  local handle = { cancelled = false }
  local watchers = sparse.new()
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
      watchers = sparse.new()

      for _, w in snapshot.iter(true) do
        defer(function()
          fire(w)
        end)
      end
    end)
  end

  handle.on_cancel = function(watcher)
    if handle.cancelled then
      fire(watcher)
      return function() end
    end

    local key = watchers.push(watcher)
    return function()
      watchers.remove(key)
    end
  end

  if deadline_ms then
    timer = vim.uv.new_timer()
    timer:start(deadline_ms, 0, handle.cancel)
  end

  if parent then
    unwatch_from_parent = parent.on_cancel(handle)
  end

  return handle
end

return M
