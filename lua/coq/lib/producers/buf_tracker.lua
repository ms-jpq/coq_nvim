---@class buf_tracker.Spec<S>
---@field compare fun(buf: integer, previous?: S): S?
---@field prune fun(settings: config.Settings, idle_ctx: idle.Ctx, stale: table<integer, S?>)
---@field index fun(settings: config.Settings, idle_ctx: idle.Ctx, computed: table<integer, S>)

local M = {}

---@generic S
---@param spec buf_tracker.Spec<S>
---@return fun(settings: config.Settings, idle_ctx: idle.Ctx)
M.new = function(spec)
  local state = {}

  return function(settings, idle_ctx)
    local stale, computed = {}, {}

    for buf in pairs(idle_ctx.removed) do
      stale[buf] = state[buf]
      state[buf] = nil
    end

    for buf in pairs(idle_ctx.updated) do
      local compared = spec.compare(buf, state[buf])

      if compared ~= nil then
        stale[buf] = state[buf]
        state[buf] = compared
        computed[buf] = compared
      end
    end

    spec.prune(settings, idle_ctx, stale)
    spec.index(settings, idle_ctx, computed)
  end
end

return M
