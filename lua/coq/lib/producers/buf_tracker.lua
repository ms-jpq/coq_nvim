---@class buf_tracker.Spec<S>
---@field compare fun(buf: integer, previous?: S): S?
---@field reindex fun(idle_ctx: idle.Ctx, stale: table<integer, S?>, computed: table<integer, S>)

local M = {}

---@generic S
---@param spec buf_tracker.Spec<S>
---@return fun(idle_ctx: idle.Ctx)
M.new = function(spec)
  local state = {}

  return function(idle_ctx)
    local stale, computed = {}, {}

    for buf in pairs(idle_ctx.removed) do
      stale[buf] = state[buf]
    end

    for buf in pairs(idle_ctx.updated) do
      local compared = spec.compare(buf, state[buf])

      if compared ~= nil then
        stale[buf] = state[buf]
        computed[buf] = compared
      end
    end

    spec.reindex(idle_ctx, stale, computed)

    for buf in pairs(idle_ctx.removed) do
      state[buf] = nil
    end
    for buf, compared in pairs(computed) do
      state[buf] = compared
    end
  end
end

return M
