local context = require "coq.lib.context"
local events_m = require "coq.completions.events"
local insertion = require "coq.completions.insertion"
local lib = require "coq.lib"

local M = {}

---@param ctx ctx.base
---@return string
M._dedup_key = function(ctx)
  local row, col = unpack(ctx.pos)
  return string.format("%d:%d:%d:%d", ctx.buf, ctx.changedtick, row, col)
end

---@param settings config.Settings
---@param ctx ctx.full
---@param prev string
---@return boolean
M._should_skip = function(settings, ctx, prev)
  if ctx.manual then
    return false
  end

  if not settings.completion.always then
    return true
  end

  if M._dedup_key(ctx) == prev then
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
---@param statsd index.Statsd
---@param resolver completions.Resolver
---@param sup producers.Producer<ctx.full>
---@param events completions.Events
M.bind = function(n, settings, statsd, resolver, sup, events)
  local prev = ""
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
    prev = M._dedup_key(ctx)

    if ev.manual and settings.completion.sticky_manual then
      sticky = true
    end

    resolver.reset()
    lib.scope(function(defer)
      local close, iter = sup.search(settings, ctx)
      defer(close)
      insertion.complete(ctx, settings, statsd, iter)
    end)
  end)
end

return M
