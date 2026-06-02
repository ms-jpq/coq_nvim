local fuzzy = require "coq.lib.index.fuzzy"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class tags.Item: tags.Tag
---@field buf integer

---@class tags.Ctx
---@field buf? integer
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<tags.Ctx, tags.Item>
M.new = function(settings)
  local prefix = settings.match.exact_matches

  ---@return index.Searcher<tags.Ctx, tags.Item>
  local name_trie = function()
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
            return item.name
          end,
        }
      end,
    }
  end

  return search.indexed {
    insert_key = function(item)
      return item.buf
    end,
    query_key = function(ctx)
      return ctx.buf
    end,
    child = name_trie,
  }
end

return M
