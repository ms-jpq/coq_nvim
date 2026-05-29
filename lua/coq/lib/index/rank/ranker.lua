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

---@param source_bias? table<string, number>
---@return index.Ranker
M.new = function(source_bias)
  local recency = {}
  source_bias = source_bias or {}

  local ranker = {}

  ranker.inserted = function(filter)
    recency[filter] = (recency[filter] or 0) + 1
  end

  ranker.prepare = function(ctx)
    return {
      token = ctx.cword,
      locality = tokens.locality(ctx.buf, tokens.surround(ctx)),
      recency = recency,
      source_bias = source_bias,
    }
  end

  ---@cast ranker index.Ranker
  return ranker
end

return M
