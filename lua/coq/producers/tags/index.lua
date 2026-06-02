local search = require "coq.lib.index"
local util = require "coq.producers.util"

---@class tags.Item: tags.Tag

---@class tags.Ctx
---@field filetype? string
---@field filename? string
---@field keyword_before? string

local M = {}

---@param settings config.Settings
---@return index.Searcher<tags.Ctx, tags.Item>
M.new = function(settings)
  local word_trie = util.word_search(settings)

  ---@return index.Searcher<tags.Ctx, tags.Item>
  local file_layer = function()
    return search.indexed {
      insert_key = function(item)
        return item.filename
      end,
      query_key = function(ctx)
        return ctx.filename
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
    child = file_layer,
  }
end

return M
