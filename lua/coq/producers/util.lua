local itertools = require "coq.lib.itertools"

local M = {}

---@param item { word: string? }
---@return string?
local word_of = function(item)
  return item.word
end

---@generic T : { word: string? }
---@param settings config.Settings
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
M.shape = function(settings, iter)
  return itertools.take(settings.match.max_results, itertools.uniq_by(word_of, iter))
end

return M
