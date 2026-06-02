local async = require "coq.lib.async"
local lib = require "coq.lib"
local worker = require "coq.lib.worker"

---@class producers.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@class producers.Producer<C>
---@field idle fun(settings: config.Settings, ctx: C)
---@field bind fun(n: async.Nursery)
---@field search fun(settings: config.Settings, ctx: C): producers.SearchIter

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
    bind = lib.noop,
    idle = function(settings, idle_ctx)
      w.queue(spec.idle, settings, idle_ctx)
    end,
    search = function(settings, ctx)
      local iter = async.wrap(function()
        lib.scope(function(defer)
          local stream = w.queue_stream(spec.matcher, settings, ctx)
          defer(stream.close)
          for item in stream do
            coroutine.yield(item)
          end
        end)
      end)

      return setmetatable({ close = lib.noop }, { __call = iter })
    end,
  }
end

return M
