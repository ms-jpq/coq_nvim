local async = require "coq.lib.async"
local match = require "coq.lib.index.rank.match"

---@class index.FuzzySpec<C, T>
---@field insert_key fun(item: T): string
---@field query_key fun(ctx: C): string?
---@field cutoff number
---@field look_ahead integer

local M = {}

---@generic C, T
---@param spec index.FuzzySpec<T>
---@return index.Searcher<C, T>
M.new = function(spec)
  ---@type table<string, any>
  local items = {}
  local fuzzy = {}

  fuzzy.insert = function(item)
    local key = spec.insert_key(item)
    items[key] = item
  end

  fuzzy.prune = function(_)
    items = {}
    return true
  end

  fuzzy.search = function(ctx)
    return async.wrap(function()
      local token = spec.query_key(ctx) or ""

      for key, entry in pairs(items) do
        local score = match.score(spec.look_ahead, token, key)
        if token == "" or score >= spec.cutoff then
          coroutine.yield { item = entry, fuzzy = score }
        end
      end
    end)
  end

  return fuzzy
end

return M
