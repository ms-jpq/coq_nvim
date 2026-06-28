local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class registers.Item
---@field word string
---@field register string
---@field linewise boolean
---@field line? string

---@class registers.Ctx
---@field register? string
---@field match_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<registers.Ctx, registers.Item>
M.new = function(settings)
  return search.indexed {
    insert_key = function(item)
      return item.register
    end,
    query_key = function(ctx)
      return ctx.register
    end,
    child = util.word_search(settings),
  }
end

return M
