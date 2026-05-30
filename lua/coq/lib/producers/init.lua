local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"
local search = require "coq.lib.index"

---@alias producers.Push fun(event: any)

---@class producers.Producer: index.Searchable
---@field idle fun(ctx: ctx.full)
---@field bind fun(n: async.Nursery, on_push?: fun(push: producers.Push))

---@alias producers.IdleFn fun(events: any[], ctx: ctx.full)
---@alias producers.MatcherFn fun(ctx: ctx.full)
---@alias producers.NewProducer fun(idle: producers.IdleFn, matcher: producers.MatcherFn): producers.Producer

local M = {}

---@type producers.NewProducer
M.new = function(idle, matcher)
  local events = queue.new()
  local ph = handle.new()
  local bound = false

  local push = function(event)
    if ph.cancelled then
      return
    end
    events.push(event)
  end

  local db = {
    bind = function(n, on_push)
      local _ = n.handle.on_cancel(ph.cancel)
      if bound then
        return
      end
      bound = true
      if on_push then
        on_push(push)
      end
    end,
  }

  db.idle = function(ctx)
    local batch = {}
    for e in events.pop do
      table.insert(batch, e)
    end
    if #batch > 0 then
      idle(batch, ctx)
    end
  end

  db.search = function(ctx)
    if ph.cancelled then
      return lib.dead_iter
    end
    local h = handle.new(runtime.current())
    return search.iter(h, function()
      matcher(ctx)
    end)
  end

  ---@cast db producers.Producer
  return db
end

return M
