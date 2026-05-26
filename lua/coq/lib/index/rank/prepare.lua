local tokens = require "coq.lib.index.tokens"

local M = {}

-- effect: precompute per-keystroke inputs ONCE from buffer + caller-supplied
-- history/config. Stage boundary -- everything downstream is pure.
M.prepare = function(ctx, recency, priors)
  return {
    token = ctx.cword,
    locality = tokens.locality(ctx.buf, tokens.surround(ctx)),
    recency = recency or {},
    priors = priors or {},
  }
end

return M
