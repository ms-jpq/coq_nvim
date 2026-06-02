local async = require "coq.lib.async"

---@class buf_tracker.Meta
---@field tick integer

---@class buf_tracker.Spec<M>
---@field fetch fun(buf: integer, prev_tick?: integer): M?
---@field reindex fun(settings: config.Settings, metas: M[])
---@field prune fun(settings: config.Settings, buf: integer)

local M = {}

---@generic M : buf_tracker.Meta
---@param spec buf_tracker.Spec<M>
---@return fun(settings: config.Settings, idle_ctx: idle.Ctx)
M.new = function(spec)
  local last_tick = {}

  return function(settings, idle_ctx)
    for buf in pairs(idle_ctx.removed) do
      async.sleep(0)
      spec.prune(settings, buf)
      last_tick[buf] = nil
    end

    local fresh = {}
    for buf in pairs(idle_ctx.updated) do
      async.sleep(0)
      local prev = last_tick[buf]
      local meta = spec.fetch(buf, prev)

      if meta ~= nil and last_tick[buf] == prev then
        last_tick[buf] = meta.tick
        spec.prune(settings, buf)
        table.insert(fresh, meta)
      end
    end

    if #fresh > 0 then
      spec.reindex(settings, fresh)
    end
  end
end

return M
