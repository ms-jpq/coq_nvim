local fuzzy = require "coq.lib.index.fuzzy"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

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
  local prefix = settings.match.exact_matches

  ---@return index.Searcher<treesitter.Ctx, treesitter.Item>
  local text_trie = function()
    return trie.new {
      insert_key = function(item)
        return item.word
      end,
      query_key = function(ctx)
        if ctx.keyword_before == "" then
          return nil
        end
        return ctx.keyword_before
      end,
      prefix = prefix,
      child = function()
        return fuzzy.new {
          insert_key = function(item)
            return item.word
          end,
        }
      end,
    }
  end

  ---@return index.Searcher<treesitter.Ctx, treesitter.Item>
  local buf_layer = function()
    return search.indexed {
      insert_key = function(item)
        return item.buf
      end,
      query_key = function(ctx)
        return ctx.buf
      end,
      child = text_trie,
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
