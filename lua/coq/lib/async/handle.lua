local lib = require "coq.lib"
local sparse = require "coq.lib.sparse_table"

local M = {}

M.new = function(parent, deadline_ms)
  local handle = { cancelled = false }
  local watchers = sparse.new()
  local unwatch_from_parent = lib.noop
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
        defer(w)
      end
    end)
  end

  ---@nodiscard
  handle.on_cancel = function(watcher)
    if handle.cancelled then
      watcher()
      return lib.noop
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
    unwatch_from_parent = parent.on_cancel(handle.cancel)
  end

  return handle
end

return M
