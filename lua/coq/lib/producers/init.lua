local async = require "coq.lib.async"
local lib = require "coq.lib"
local worker = require "coq.lib.worker"

---@class producers.Producer<C>: index.Searchable<C, completions.Item>
---@field idle fun(ctx: C)
---@field bind fun(n: async.Nursery)
---@field max_pulls integer

---@class producers.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@alias producers.IdleFn<C> fun(settings: config.Settings?, events: table<any, any>, ctx: C)
---@alias producers.MatcherFn<C> fun(settings: config.Settings?, ctx: C)
---@alias producers.OnBind fun(n: async.Nursery)
---@alias producers.DrainFn fun(): table<any, any>

---@class producers.Spec<C>
---@field settings? config.Settings
---@field idle producers.IdleFn<C>
---@field matcher producers.MatcherFn<C>
---@field bind producers.OnBind
---@field drain? producers.DrainFn
---@field max_pulls integer

local M = {}

---@generic C
---@param spec producers.Spec<C>
---@return producers.Producer<C>
M.threaded = function(spec)
  local w = worker.spawn()

  return {
    max_pulls = spec.max_pulls,
    bind = spec.bind,
    idle = function(ctx)
      local batch = spec.drain and spec.drain() or {}
      w.queue(spec.idle, spec.settings, batch, ctx)
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
