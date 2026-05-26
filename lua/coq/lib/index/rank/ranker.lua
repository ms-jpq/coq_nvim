local tokens = require "coq.lib.index.tokens"

local M = {}

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

  return ranker
end

return M
