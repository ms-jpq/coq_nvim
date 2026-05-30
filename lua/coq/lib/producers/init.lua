local handle = require "coq.lib.async.handle"
local runtime = require "coq.lib.async.runtime"
local search = require "coq.lib.index"

---@class producers.Producer: index.Searchable
---@field idle fun(ctx: ctx.full)
---@field bind fun(n: async.Nursery)

---@alias producers.KeyFn fun(ev: any): any
---@alias producers.IdleFn fun(events: table<any, any>, ctx: ctx.full)
---@alias producers.MatcherFn fun(ctx: ctx.full)
---@alias producers.Push fun(ev: any)
---@alias producers.OnBind fun(n: async.Nursery, push: producers.Push)

---@class producers.Spec
---@field key? producers.KeyFn
---@field idle producers.IdleFn
---@field matcher producers.MatcherFn
---@field bind producers.OnBind

---@alias producers.NewProducer fun(spec: producers.Spec): producers.Producer

local M = {}

---@type producers.NewProducer
M.new = function(spec)
  local key = spec.key or function(ev)
    return ev
  end
  local location = {}

  local db = {}

  db.bind = function(n)
    spec.bind(n, function(ev)
      location[key(ev)] = ev
    end)
  end

  db.idle = function(ctx)
    local batch = location
    location = {}
    spec.idle(batch, ctx)
  end

  db.search = function(ctx)
    local h = handle.new(runtime.current())
    return search.iter(h, function()
      spec.matcher(ctx)
    end)
  end

  ---@cast db producers.Producer
  return db
end

return M
