local async = require "coq.lib.async"

---@class buf_tracker.Meta
---@field tick integer

---@class buf_tracker.Spec<M>
---@field fetch fun(buf: integer, prev_tick?: integer): M?
---@field reindex fun(metas: M[])
---@field prune fun(buf: integer)

local M = {}

---@generic M : buf_tracker.Meta
---@param spec buf_tracker.Spec<M>
---@return fun(diff: { updated: table<integer, true>, removed: table<integer, true> })
M.new = function(spec)
  local last_tick = {}

  return function(diff)
    for buf in pairs(diff.removed) do
      async.sleep(0)
      spec.prune(buf)
      last_tick[buf] = nil
    end

    local fresh = {}
    for buf in pairs(diff.updated) do
      async.sleep(0)
      local prev = last_tick[buf]
      local meta = spec.fetch(buf, prev)

      if meta ~= nil and last_tick[buf] == prev then
        last_tick[buf] = meta.tick
        spec.prune(buf)
        table.insert(fresh, meta)
      end
    end

    if #fresh > 0 then
      spec.reindex(fresh)
    end
  end
end

return M
