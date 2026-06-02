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
---@field push fun(buf: integer, kind: 'update' | 'remove')
---@field drain fun(): table<integer, buf_tracker.Event>
---@field idle fun(_: any, events: table<integer, buf_tracker.Event>)
---@field state buf_tracker.State

local M = {}

---@generic M : buf_tracker.Meta
---@param spec buf_tracker.Spec<M>
---@return buf_tracker.Tracker
M.new = function(spec)
  local tracker = {
    ---@type buf_tracker.State
    state = { last_tick = {} },
  }

  local pending = {}

  tracker.push = function(buf, kind)
    pending[buf] = { kind = kind }
  end

  tracker.drain = function()
    local p = pending
    pending = {}
    return p
  end

  tracker.idle = function(_, events)
    for buf, ev in pairs(events) do
      async.sleep(0)
      if ev.kind == "remove" then
        spec.prune(buf)
        tracker.state.last_tick[buf] = nil
      elseif ev.kind == "update" then
        local prev = tracker.state.last_tick[buf]
        local meta = spec.fetch(buf, prev)

        if meta ~= nil and tracker.state.last_tick[buf] == prev then
          tracker.state.last_tick[buf] = meta.tick
          spec.prune(buf)
          spec.reindex(meta)
        end
      end
    end
  end

  ---@cast tracker buf_tracker.Tracker
  return tracker
end

return M
