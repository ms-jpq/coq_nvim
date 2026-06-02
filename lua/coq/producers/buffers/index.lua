local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class buffer.Item
---@field word string
---@field buf integer
---@field filetype string
---@field filename string

---@class buffer.Ctx
---@field buf? integer
---@field filetype? string
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<buffer.Ctx, buffer.Item>
M.new = function(settings)
  local word_trie = util.word_search(settings)

  ---@return index.Searcher<buffer.Ctx, buffer.Item>
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
