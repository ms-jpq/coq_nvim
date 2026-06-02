local atools = require "coq.lib.atools"
local lru = require "coq.lib.lru"
local tokens = require "coq.lib.index.tokens"

local RECENCY_CAP = 888

---@class index.Prepared
---@field token string
---@field locality table<string, integer>
---@field recency table<string, integer>
---@field source_bias table<string, number>

---@class index.Ranker
---@field inserted fun(filter: string)
---@field prepare fun(ctx: ctx.full): index.Prepared

local M = {}

---@param clients config.Clients
---@return index.Ranker
M.new = function(clients)
  local source_bias = {}
  for _, client in pairs(clients) do
    if client.enabled and client.short_name then
      source_bias[client.short_name] = 1 + (client.weight_adjust or 0)
    end
  end

  local recency = lru.new(RECENCY_CAP)
  local ranker = {}

  ranker.inserted = function(filter)
    recency[filter] = (recency[filter] or 0) + 1
  end

  ranker.prepare = function(ctx)
    atools.scheduled()
    return {
      token = ctx.cword,
      locality = tokens.locality(ctx.kw, vim.iter(tokens.surround(ctx)) --[[@as lib.Iterator<string>]]),
      recency = recency,
      source_bias = source_bias,
    }
  end

  ---@cast ranker index.Ranker
  return ranker
end

return M
