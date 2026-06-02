local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class treesitter.Node
---@field text string
---@field kind string

---@class treesitter.Item
---@field buf integer
---@field filetype string
---@field filename string
---@field word string
---@field kind string
---@field range integer[]
---@field parent? treesitter.Node
---@field grandparent? treesitter.Node

---@class treesitter.Ctx
---@field buf? integer
---@field filetype? string
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<treesitter.Ctx, treesitter.Item>
M.new = function(settings)
  local word_trie = util.word_search(settings)

  ---@return index.Searcher<treesitter.Ctx, treesitter.Item>
  local buf_layer = function()
    return search.indexed {
      insert_key = function(item)
        return item.buf
      end,
      query_key = function(ctx)
        return ctx.buf
      end,
      child = word_trie,
    }
  end

  return search.indexed {
    insert_key = function(item)
      return item.filetype
    end,
    query_key = function(ctx)
      return ctx.filetype
    end,
    child = buf_layer,
  }
end

return M
