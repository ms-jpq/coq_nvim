local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local ghost = require "coq.completions.ghost"
local inserted = require "coq.completions.inserted"
local item = require "coq.completions.item"
local lib = require "coq.lib"
local rank = require "coq.lib.index.rank"

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param resolver completions.Resolver
---@param statsd index.Statsd
M.bind = function(n, settings, resolver, statsd)
  vim.api.nvim_create_autocmd("CompleteDone", {
    group = lib.group,
    callback = async.entry(errs.with_reporting(function()
      local user_data = vim.v.completed_item.user_data
      if type(user_data) ~= "table" or not user_data.meta then
        return
      end

      ---@cast user_data completions.Item
      local shift = inserted.apply(context.full(), user_data)
      statsd.inserted(user_data)
      if user_data.meta.lsp then
        local ctx = context.full()
        n.spawn(function()
          inserted.resolve(settings, ctx, resolver, user_data, shift)
        end)
      end
    end)),
  })
end

---@param ctx ctx.full
---@param settings config.Settings
---@param history table<string, integer>
---@param iter lib.Iterator<rank.Measured[]>
M.complete = function(ctx, settings, history, iter)
  local ranker = rank.new(settings, history, ctx)
  for batch in iter do
    ranker.add(batch)
  end

  local ranked = ranker.rank(settings.match.max_results)

  atools.scheduled()
  if not context.still_valid(ctx) or string.sub(vim.api.nvim_get_mode().mode, 1, 1) ~= "i" then
    return
  end

  if settings.display.ghost_text.enabled then
    ghost.show(ctx, ranked[1])
  end

  local items = vim
    .iter(ranked)
    :map(function(i)
      return item.to_nvim(settings.display.icons, i)
    end)
    :totable()

  local start = #ctx.line_before - #ctx.keyword_before + 1
  vim.fn.complete(start, items)
end

return M
