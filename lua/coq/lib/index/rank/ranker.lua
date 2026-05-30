local tokens = require "coq.lib.index.tokens"

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

  local recency = {}
  local ranker = {}

  ranker.inserted = function(filter)
    recency[filter] = (recency[filter] or 0) + 1
  end

  ranker.prepare = function(ctx)
    return {
      token = ctx.cword,
      locality = tokens.locality(
        tokens.parse_iskeyword(ctx.iskeyword),
        vim.iter(tokens.surround(ctx)) --[[@as fun(): string?]]
      ),
      recency = recency,
      source_bias = source_bias,
    }
  end

  ---@cast ranker index.Ranker
  return ranker
end

return M
