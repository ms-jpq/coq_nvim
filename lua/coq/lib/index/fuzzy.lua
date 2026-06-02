local async = require "coq.lib.async"

---@class index.FuzzySpec<T>
---@field insert_key fun(item: T): any

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

  fuzzy.search = function(_)
    return async.wrap(function()
      for _, item in pairs(items) do
        coroutine.yield(item)
      end
    end)
  end

  return fuzzy
end

return M
