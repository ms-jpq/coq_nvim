local async = require "coq.lib.async"

---@class buf_tracker.Meta
---@field tick integer

---@alias buf_tracker.Event { kind: 'update' | 'remove' }

---@class buf_tracker.Spec<M>
---@field fetch fun(buf: integer, prev_tick?: integer): M?
---@field reindex fun(meta: M)
---@field prune fun(buf: integer)

---@class buf_tracker.State
---@field last_tick table<integer, integer>

---@class buf_tracker.Tracker
---@field idle fun(_: any, events: table<integer, buf_tracker.Event>)
---@field state buf_tracker.State

local M = {}

---@generic M : buf_tracker.Meta
---@param spec buf_tracker.Spec<M>
---@return buf_tracker.Tracker
M.new = function(spec)
  ---@type buf_tracker.State
  local state = { last_tick = {} }

  local update = function(buf)
    local meta = spec.fetch(buf, state.last_tick[buf])
    if meta == nil then
      return
    end
    state.last_tick[buf] = meta.tick
    spec.prune(buf)
    spec.reindex(meta)
  end

  local idle = function(_, events)
    for buf, ev in pairs(events) do
      async.sleep(0)
      if ev.kind == "remove" then
        spec.prune(buf)
        state.last_tick[buf] = nil
      elseif ev.kind == "update" then
        update(buf)
      end
    end
  end

  return { idle = idle, state = state }
end

return M
