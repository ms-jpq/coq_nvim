local async = require "coq.lib.async"
local lib = require "coq.lib"
local worker = require "coq.lib.worker"

---@class producers.Producer<C>: index.Searchable<C, completions.Item>
---@field idle fun(ctx: C)
---@field bind fun(n: async.Nursery)
---@field max_pulls integer

---@class producers.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@alias producers.IdleFn<C> fun(settings: config.Settings?, idle_ctx: C)
---@alias producers.MatcherFn<C> fun(settings: config.Settings?, ctx: C)

---@class producers.Spec<C>
---@field settings? config.Settings
---@field idle producers.IdleFn<C>
---@field matcher producers.MatcherFn<C>
---@field max_pulls integer

local M = {}

---@generic C
---@param spec producers.Spec<C>
---@return producers.Producer<C>
M.threaded = function(spec)
  local w = worker.spawn()

  return {
    max_pulls = spec.max_pulls,
    bind = lib.noop,
    idle = function(idle_ctx)
      w.queue(spec.idle, spec.settings, idle_ctx)
    end,
    search = function(ctx)
      return async.wrap(function()
        lib.scope(function(defer)
          local stream = w.queue_stream(spec.matcher, spec.settings, ctx)
          defer(stream.close)
          for item in stream do
            coroutine.yield(item)
          end
        end)
      end)
    end,
  }
end

return M
