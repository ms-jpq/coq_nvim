local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class snippets.Item
---@field word string
---@field body string
---@field filetype string
---@field label string
---@field doc string

---@class snippets.Ctx
---@field filetype? string
---@field match_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<snippets.Ctx, snippets.Item>
M.new = function(settings)
  return search.indexed {
    insert_key = function(item)
      return item.filetype
    end,
    query_key = function(ctx)
      return ctx.filetype
    end,
    child = util.word_search(settings),
  }
end

return M
