local fuzzy = require "coq.lib.index.fuzzy"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class snippets.Item
---@field word string
---@field body string
---@field filetype string
---@field label? string
---@field doc? string

---@class snippets.Ctx
---@field filetype? string
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<snippets.Ctx, snippets.Item>
M.new = function(settings)
  local prefix = settings.match.exact_matches

  ---@return index.Searcher<snippets.Ctx, snippets.Item>
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

  return search.indexed {
    insert_key = function(item)
      return item.filetype
    end,
    query_key = function(ctx)
      return ctx.filetype
    end,
    child = word_trie,
  }
end

return M
