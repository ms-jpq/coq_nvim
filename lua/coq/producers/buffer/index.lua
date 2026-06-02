local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

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

---@param _ config.Settings
---@return index.Searcher<buffer.Ctx, buffer.Item>
M.new = function(_)
  ---@return index.Searcher<buffer.Ctx, buffer.Item>
  local word_trie = function()
    return trie.new {
      insert_key = function(item)
        return item.word
      end,
      query_key = function(ctx)
        if ctx.keyword_before == nil or ctx.keyword_before == "" then
          return nil
        end
        return ctx.keyword_before
      end,
    }
  end

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
