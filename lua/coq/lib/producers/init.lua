local handle = require "coq.lib.async.handle"
local queue = require "coq.lib.queue"
local runtime = require "coq.lib.async.runtime"
local util = require "coq.lib.producers.util"

---@class producers.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@class producers.Producer: lib.Closable
---@field notify fun(event: any)
---@field idle fun(ctx: ctx.full)
---@field search fun(ctx: ctx.full): producers.SearchIter

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
      return util.dead_iter
    end
    local h = handle.new(runtime.current())

    local stream = runtime.wrap(function()
      matcher(ctx)
    end, h)

    local it = { close = h.cancel }

    local next = function()
      if h.cancelled then
        return nil
      end
      local item = stream()
      if item == nil then
        h.cancel()
      end
      return item
    end

    return setmetatable(it, { __call = next })
  end

  ---@cast db producers.Producer
  return db
end

return M
