local async = require "coq.lib.async"
local match = require "coq.lib.index.rank.match"

---@class index.FuzzySpec<C, T>
---@field insert_key fun(item: T): string
---@field query_key fun(ctx: C): string?

local M = {}

---@generic C, T
---@param spec index.FuzzySpec<T>
---@return index.Searcher<C, T>
M.new = function(spec)
  local items = {}
  local fuzzy = {}

  fuzzy.insert = function(item)
    items[spec.insert_key(item)] = item
  end

  fuzzy.prune = function(_)
    items = {}
    return true
  end

  fuzzy.search = function(ctx)
    return async.wrap(function()
      local token = spec.query_key(ctx) or ""
      for key, item in pairs(items) do
        coroutine.yield { item = item, fuzzy = match.score(token, key) }
      end
    end)
  end

  return fuzzy
end

return M
