---@class buf_tracker.Change<S>
---@field [1] boolean
---@field [2] S?
---@field [3] S?

---@class buf_tracker.Spec<S>
---@field compare fun(buf: integer, previous?: S): S?
---@field reindex fun(idle_ctx: idle.Ctx, changes: table<integer, buf_tracker.Change<S>>)

local M = {}

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
