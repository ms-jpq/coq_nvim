local async = require "coq.lib.async"

---@class buf_tracker.Meta
---@field tick integer

---@class buf_tracker.Spec<M>
---@field compare fun(buf: integer, previous?: M): M?
---@field prune fun(settings: config.Settings, bufs: integer[])
---@field index fun(settings: config.Settings, compared: M[])

local M = {}

---@generic M : buf_tracker.Meta
---@param spec buf_tracker.Spec<M>
---@return fun(settings: config.Settings, idle_ctx: idle.Ctx)
M.new = function(spec)
  local state = {}

  return function(settings, idle_ctx)
    local stale, computed = {}, {}

    for buf in pairs(idle_ctx.removed) do
      table.insert(stale, buf)
      state[buf] = nil
    end

    for buf in pairs(idle_ctx.updated) do
      local compared = spec.compare(buf, state[buf])

      if compared ~= nil then
        state[buf] = compared
        table.insert(stale, buf)
        table.insert(computed, compared)
      end
    end

    if #stale > 0 then
      spec.prune(settings, stale)
    end
    if #computed > 0 then
      spec.index(settings, computed)
    end
  end
end

return M
