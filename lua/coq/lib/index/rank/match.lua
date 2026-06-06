local hybrid = require "coq.lib.index.rank.hybrid"

local M = {}

---@param token string
---@param candidate string
---@return number score
M.score = function(token, candidate)
  if token == "" then
    return 0
  end
  return hybrid.score(token, candidate) or 0
end

return M
