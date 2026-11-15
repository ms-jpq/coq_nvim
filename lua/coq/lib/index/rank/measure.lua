local match = require "coq.lib.index.rank.match"
local tokens = require "coq.lib.index.tokens"

local M = {}

---@class rank.Features: match.Metrics
---@field proximity integer

---@class rank.Measured
---@field item completions.Item
---@field metrics rank.Features

---@param settings config.Settings
---@param ctx ctx.full
---@param items completions.Item[]
---@return rank.Measured[]
M.batch = function(settings, ctx, items)
  local charset = tokens.parse_charset(ctx.iskeyword)
  local texts = {
    [tokens.KW] = ctx.keyword_before,
    [tokens.SYM] = ctx.symbol_before,
    [tokens.WS] = string.match(ctx.line_before, "%s*$") or "",
  }

  return vim
    .iter(items)
    :map(function(item)
      local filter = item.meta.filter
      local kind = charset[string.byte(filter)] or tokens.SYM
      local match_text = texts[kind]
      if not ctx.keyword_before_has_upper then
        match_text = string.lower(match_text)
        filter = string.lower(filter)
      end
      local metrics = match.metrics(settings.match.look_ahead, match_text, filter)
      return {
        item = item,
        metrics = {
          prefix_matches = metrics.prefix_matches,
          edit_distance = metrics.edit_distance,
          proximity = ctx.locality[item.meta.filter] or 0,
        },
      }
    end)
    :totable()
end

return M
