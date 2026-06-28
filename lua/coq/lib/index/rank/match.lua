local hybrid = require "coq.lib.index.rank.hybrid"

local M = {}

---@param token string
---@param candidate string
---@param precomputed? hybrid.Precomputed
---@return number score
M.score = function(token, candidate, precomputed)
  if token == "" then
    return 0
  end
  return hybrid.score(token, candidate, precomputed) or 0
end

M.precompute = hybrid.precompute

return M
