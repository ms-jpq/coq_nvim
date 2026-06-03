local atools = require "coq.lib.atools"
local worker = require "coq.lib.worker"

local M = {}

---@param token string
---@param candidate string
---@return integer score
M._raw = function(token, candidate)
  atools.scheduled()
  local matches, _, scores = unpack(vim.fn.matchfuzzypos({ candidate }, token))
  return matches[1] ~= nil and scores[1] or 0
end

---@param token string
---@param candidate string
---@return integer score
M.score = function(token, candidate)
  if token == "" then
    return 0
  end

  if vim.is_thread() then
    return worker.main(function(t, c)
      return require("coq.lib.index.rank.match")._raw(t, c)
    end, token, candidate)
  end

  return M._raw(token, candidate)
end

return M
