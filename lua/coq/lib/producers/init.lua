local async = require "coq.lib.async"
local lib = require "coq.lib"
local worker = require "coq.lib.worker"

---@class producers.Producer<C>: index.Searchable<C, completions.Item>
---@field idle fun(ctx: C)
---@field bind fun(n: async.Nursery)
---@field max_pulls integer

---@class producers.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@alias producers.KeyFn fun(ev: any): any
---@alias producers.IdleFn<C> fun(settings: config.Settings?, events: table<any, any>, ctx: C)
---@alias producers.MatcherFn<C> fun(settings: config.Settings?, ctx: C)
---@alias producers.Push fun(ev: any)
---@alias producers.OnBind fun(n: async.Nursery, push: producers.Push)

---@class producers.Spec<C>
---@field settings? config.Settings
---@field key? producers.KeyFn
---@field idle? producers.IdleFn<C>
---@field matcher producers.MatcherFn<C>
---@field bind? producers.OnBind
---@field max_pulls? integer

local M = {}

---@generic C
---@param spec producers.Spec<C>
---@return producers.Producer<C>
M.new = function(spec)
  local w = worker.spawn()
  local key = spec.key
  local location = key and {}

  return {
    max_pulls = spec.max_pulls or math.huge,
    bind = function(n)
      if spec.bind then
        spec.bind(n, function(ev)
          if location then
            location[key(ev)] = ev
          end
        end)
      end
    end,
    idle = function(ctx)
      if not spec.idle then
        return
      end
      local batch = location or {}
      if location then
        location = {}
      end
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
