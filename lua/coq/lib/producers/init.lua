local closable = require "coq.lib.closable"
local worker = require "coq.lib.worker"

---@class producers.Producer<C>
---@field idle fun(settings: config.Settings, ctx: C)
---@field search fun(settings: config.Settings, ctx: C): fun(), lib.Iterator<completions.Item[]>

---@alias producers.IdleFn<C> fun(settings: config.Settings?, idle_ctx: C)
---@alias producers.MatcherFn<C> fun(settings: config.Settings?, ctx: C)

---@class producers.Spec<C>
---@field idle producers.IdleFn<C>
---@field matcher producers.MatcherFn<C>

local M = {}

---@generic C
---@param spec producers.Spec<C>
---@return producers.Producer<C>
M.threaded = function(spec)
  local w = worker.spawn()

  return {
    idle = function(settings, idle_ctx)
      w.queue(spec.idle, settings, idle_ctx)
    end,
    search = function(settings, ctx)
      return closable.iter(function(defer)
        local close, stream = w.queue_stream(spec.matcher, settings, ctx)
        defer(close)
        for batch in stream do
          coroutine.yield(batch)
        end
      end)
    end,
  }
end

return M
