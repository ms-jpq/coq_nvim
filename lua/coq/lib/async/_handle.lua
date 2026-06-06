local lib = require "coq.lib"
local sparse = require "coq.lib.sparse_table"

---@class async.Handle
---@field cancelled boolean
---@field cancel fun()
---@field on_cancel fun(watcher: fun()): fun()

local M = {}

---@param parent? async.Handle
---@return async.Handle
M.new = function(parent)
  ---@diagnostic disable-next-line: missing-fields
  local handle = {} ---@type async.Handle

  handle.cancelled = false
  local watchers = sparse.new()
  local unwatch = lib.noop

  handle.cancel = function()
    if handle.cancelled then
      return
    end
    handle.cancelled = true

    lib.scope(function(defer)
      defer(unwatch)

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

  if parent then
    unwatch = parent.on_cancel(handle.cancel)
  end

  return handle
end

return M
