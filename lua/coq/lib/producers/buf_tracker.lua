local async = require "coq.lib.async"

---@class buf_tracker.Change<S>
---@field [1] boolean -- deleted
---@field [2] S?      -- prev
---@field [3] S?      -- curr

---@class buf_tracker.Entry<S, T>
---@field buf integer
---@field deleted boolean
---@field prev S?
---@field curr S?
---@field data T?

---@class buf_tracker.Spec<S>
---@field compare fun(buf: integer, previous?: S): S?
---@field reindex fun(idle_ctx: idle.Ctx, changes: table<integer, buf_tracker.Change<S>>)

local M = {}

---@generic S, T
---@param changes table<integer, buf_tracker.Change<S>>
---@param fetch fun(buf: integer, curr: S): T
---@return fun() close
---@return fun(): integer?, buf_tracker.Entry<S, T>?
M.merged = function(changes, fetch)
  local iters = {}
  for buf, change in pairs(changes) do
    local deleted, prev, curr = unpack(change)
    table.insert(
      iters,
      async.wrap(function()
        coroutine.yield {
          buf = buf,
          deleted = deleted,
          prev = prev,
          curr = curr,
          data = curr ~= nil and fetch(buf, curr) or nil,
        }
      end)
    )
  end
  return async.merge(iters)
end

---@generic S
---@param spec buf_tracker.Spec<S>
---@return fun(idle_ctx: idle.Ctx)
M.new = function(spec)
  local state = {}

  return function(idle_ctx)
    local changes = {}

    for buf in pairs(idle_ctx.removed) do
      changes[buf] = { true, state[buf], nil }
    end

    for buf in pairs(idle_ctx.updated) do
      local compared = spec.compare(buf, state[buf])

      if compared ~= nil then
        changes[buf] = { false, state[buf], compared }
      end
    end

    spec.reindex(idle_ctx, changes)

    for buf, change in pairs(changes) do
      local deleted, _, curr = unpack(change)
      if deleted then
        state[buf] = nil
      else
        state[buf] = curr
      end
    end
  end
end

return M
