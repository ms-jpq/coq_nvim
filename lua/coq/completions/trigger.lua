local context = require "coq.lib.context"
local events = require "coq.completions.events"
local insertion = require "coq.completions.insertion"

local M = {}

---@param skip_after string[]
---@param line_before string
---@return boolean
local should_skip = function(skip_after, line_before)
  for _, suffix in pairs(skip_after) do
    if suffix ~= "" and string.sub(line_before, -#suffix) == suffix then
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
---@param trigger channels.Broadcast<nil>
M.bind = function(n, settings, ranker, resolver, sup, trigger)
  events.subscribe_latest(n, trigger, function()
    local ctx = context.full()
    if should_skip(settings.completion.skip_after, ctx.line_before) then
      return
    end

    resolver.reset()
    insertion.complete(ctx, settings, ranker, sup.search(settings, ctx))
  end)
end

return M
