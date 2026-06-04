local atools = require "coq.lib.atools"
local itertools = require "coq.lib.itertools"
local tokens = require "coq.lib.index.tokens"

---@class index.Prepared
---@field token string
---@field locality table<string, integer>
---@field recency table<string, integer>
---@field source_bias table<string, number>

---@class index.Statsd
---@field inserted fun(filter: string)
---@field prepare fun(ctx: ctx.full): index.Prepared

local M = {}

-- https://github.com/neovim/neovim/blob/master/src/nvim/fuzzy.c
M.WEIGHTS = { prox = 100, recen = 50 }
M.ALWAYS_TOP = 1e9

---@param prepared index.Prepared
---@param item completions.Item
---@return number
M.score = function(prepared, item)
  local meta = item.meta
  local prox = prepared.locality[meta.filter] or 0
  local recen = prepared.recency[meta.filter] or 0
  local bias = prepared.source_bias[meta.source] or 1
  local tier = meta.always_on_top and M.ALWAYS_TOP or 0

  return (meta.fuzzy + prox * M.WEIGHTS.prox + recen * M.WEIGHTS.recen) * bias + tier
end

---@param clients config.Clients
---@return index.Statsd
M.new = function(clients)
  local source_bias = {}
  for _, client in pairs(clients) do
    if client.enabled and client.short_name then
      source_bias[client.short_name] = 1 + (client.weight_adjust or 0)
    end
  end

  local recency = {}
  ---@diagnostic disable-next-line: missing-fields
  local statsd = {} ---@type index.Statsd

  statsd.inserted = function(filter)
    recency[filter] = (recency[filter] or 0) + 1
  end

  statsd.prepare = function(ctx)
    atools.scheduled()
    return {
      token = ctx.keyword_before,
      locality = tokens.locality(
        ctx.kw,
        itertools.intersperse(ctx.linesep, vim.iter(tokens.surround(ctx)) --[[@as lib.Iterator<string>]])
      ),
      recency = recency,
      source_bias = source_bias,
    }
  end

  return statsd
end

return M
