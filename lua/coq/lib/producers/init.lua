local async = require "coq.lib.async"

---@class producers.Producer<C>: index.Searchable<C, completions.Item>
---@field idle fun(ctx: C)
---@field bind fun(n: async.Nursery)
---@field max_pulls integer

---@alias producers.KeyFn fun(ev: any): any
---@alias producers.IdleFn<C> fun(settings: config.Settings?, events: table<any, any>, ctx: C)
---@alias producers.MatcherFn<C> fun(settings: config.Settings?, ctx: C)
---@alias producers.Push fun(ev: any)
---@alias producers.OnBind fun(n: async.Nursery, push: producers.Push)

---@class producers.Spec<C>
---@field settings? config.Settings
---@field key? producers.KeyFn
---@field idle producers.IdleFn<C>
---@field matcher producers.MatcherFn<C>
---@field bind producers.OnBind
---@field max_pulls? integer

local M = {}

---@generic C
---@param spec producers.Spec<C>
---@return producers.Producer<C>
M.new = function(spec)
  local key = spec.key or function(ev)
    return ev
  end
  local location = {}

  local db = { max_pulls = spec.max_pulls or math.huge }

  db.bind = function(n)
    spec.bind(n, function(ev)
      location[key(ev)] = ev
    end)
  end

  db.idle = function(ctx)
    local batch = location
    location = {}
    spec.idle(spec.settings, batch, ctx)
  end

  db.search = function(ctx)
    return async.wrap(function()
      spec.matcher(spec.settings, ctx)
    end)
  end

  ---@cast db producers.Producer
  return db
end

return M
