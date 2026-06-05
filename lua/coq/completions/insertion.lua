local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local inserted = require "coq.completions.inserted"
local item = require "coq.completions.item"
local statsd_m = require "coq.lib.index.rank.statsd"
local topk_m = require "coq.lib.index.rank.topk"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param resolver completions.Resolver
---@param statsd index.Statsd
---@param done channels.Broadcast<vim.v.completed_item>
M.bind = function(n, settings, resolver, statsd, done)
  events.subscribe_latest(n, done, function(completed)
    local user_data = completed.user_data
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

  local items = {}
  for i in topk.iter() do
    table.insert(items, item.to_nvim(settings.display.icons, i))
  end

  atools.scheduled()
  if not context.still_valid(ctx) or string.sub(vim.api.nvim_get_mode().mode, 1, 1) ~= "i" then
    return
  end

  local start = #ctx.line_before - #ctx.keyword_before + 1
  vim.fn.complete(start, items)
end

return M
