local context = require "coq.lib.context"
local events_m = require "coq.completions.events"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"

local M = {}

---@param settings config.Settings
---@param ctx ctx.full
---@param prev { buf: integer, tick: integer }
---@return boolean
M._should_skip = function(settings, ctx, prev)
  if ctx.manual then
    return false
  end

  if not settings.completion.always then
    return true
  end

  if prev.buf == ctx.buf and prev.tick == ctx.changedtick then
    return true
  end

  for _, suffix in pairs(settings.completion.skip_after) do
    if suffix ~= "" and string.sub(ctx.line_before, -#suffix) == suffix then
      return true
    end
  end

  return false
end

---@param n async.Nursery
---@param settings config.Settings
---@param ranker index.Ranker
---@param resolver completions.Resolver
---@param sup producers.Producer<ctx.full>
---@param events completions.Events
M.bind = function(n, settings, ranker, resolver, sup, events)
  local prev = { buf = -1, tick = -1 }
  local sticky = false

  events_m.subscribe_latest(n, events.leave, function()
    sticky = false
  end)

  events_m.subscribe_latest(n, events.trigger, function(ev)
    local manual = ev.manual or sticky
    local ctx = context.full { manual = manual }

    if M._should_skip(settings, ctx, prev) then
      return
    end
    prev = { buf = ctx.buf, tick = ctx.changedtick }

    if ev.manual and settings.completion.sticky_manual then
      sticky = true
    end

    resolver.reset()
    lib.scope(function(defer)
      local close, iter = sup.search(settings, ctx)
      defer(close)
      insertion.complete(ctx, settings, ranker, iter)
    end)
  end)
end

return M
