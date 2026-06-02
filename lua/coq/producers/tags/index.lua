local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class tags.Item: tags.Tag
---@field buf integer

---@class tags.Ctx
---@field buf? integer
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<tags.Ctx, tags.Item>
M.new = function(settings)
  return search.indexed {
    insert_key = function(item)
      return item.buf
    end,
    query_key = function(ctx)
      return ctx.buf
    end,
    child = util.word_search(settings),
  }
end

return M
