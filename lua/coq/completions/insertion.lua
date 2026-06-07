local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local ghost = require "coq.completions.ghost"
local inserted = require "coq.completions.inserted"
local item = require "coq.completions.item"
local statsd_m = require "coq.lib.index.rank.statsd"
local topk_m = require "coq.lib.index.rank.topk"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param resolver completions.Resolver
---@param statsd index.Statsd
---@param pum channels.Broadcast<completions.PumEvent>
M.bind = function(n, settings, resolver, statsd, pum)
  events.subscribe_latest(n, pum, function(ev)
    if ev.kind ~= "done" then
      return
    end
    local user_data = ev.completed_item.user_data
    if type(user_data) ~= "table" then
      return
    end

    ---@cast user_data completions.Item
    local ctx = context.full()
    if inserted.apply(settings, ctx, resolver, user_data) then
      statsd.inserted(user_data)
    end
  end)
end

---@param ctx ctx.full
---@param settings config.Settings
---@param statsd index.Statsd
---@param iter lib.Iterator<completions.Item[]>
M.complete = function(ctx, settings, statsd, iter)
  local prepared = statsd.prepare(ctx)

  local topk = topk_m.new(settings.match.max_results, item.dedup_key)
  for batch in iter do
    for _, i in ipairs(batch) do
      topk.push(i, statsd_m.score(prepared, i))
    end
  end

  local ranked = {}
  for i in topk.iter() do
    table.insert(ranked, i)
  end

  atools.scheduled()
  if not context.still_valid(ctx) or string.sub(vim.api.nvim_get_mode().mode, 1, 1) ~= "i" then
    return
  end

  -- proactive top-1 ghost: render the best match inline before the PUM opens.
  -- When no match exists, clear so a stale ghost from a prior trigger doesn't
  -- linger across the keystroke.
  local g = settings.display.ghost_text
  if g.proactive then
    if ranked[1] then
      ghost.show(g, ctx, ranked[1], 1, #ranked)
    else
      ghost.clear(ctx.buf)
    end
  end

  local items = {}
  for _, i in pairs(ranked) do
    table.insert(items, item.to_nvim(settings.display.icons, i))
  end

  local start = #ctx.line_before - #ctx.keyword_before + 1
  vim.fn.complete(start, items)
end

return M
