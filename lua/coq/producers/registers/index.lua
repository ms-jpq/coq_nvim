local fuzzy = require "coq.lib.index.fuzzy"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class registers.Item
---@field word string
---@field register string
---@field linewise boolean
---@field line? string

---@class registers.Ctx
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<registers.Ctx, registers.Item>
M.new = function(settings)
  local prefix = settings.match.exact_matches

  ---@return index.Searcher<registers.Ctx, registers.Item>
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
      return item.register
    end,
    query_key = function(_)
      return nil
    end,
    child = word_trie,
  }
end

return M
