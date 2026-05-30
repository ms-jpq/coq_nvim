local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"
local search = require "coq.lib.index.search"

---@class producers.Producer: index.Searchable
---@field notify fun(event: any)
---@field idle fun(ctx: ctx.full)

---@alias producers.IdleFn fun(events: any[], ctx: ctx.full)
---@alias producers.MatcherFn fun(ctx: ctx.full)
---@alias producers.NewProducer fun(idle: producers.IdleFn, matcher: producers.MatcherFn): producers.Producer

local M = {}

---@type producers.NewProducer
M.new = function(idle, matcher)
  local events = queue.new()
  local closed = false

  local db = {}

  db.close = function()
    closed = true
  end

  db.notify = function(event)
    if closed then
      return
    end
    events.push(event)
  end

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
    if closed then
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
