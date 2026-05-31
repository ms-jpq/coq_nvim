local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class treesitter.Node
---@field text string
---@field kind string

---@class treesitter.Item
---@field buf integer
---@field filetype string
---@field filename string
---@field text string
---@field kind string
---@field range integer[]
---@field parent? treesitter.Node
---@field grandparent? treesitter.Node

---@class treesitter.Ctx
---@field buf? integer
---@field filetype? string
---@field keyword_before? string

---@return index.Searcher<treesitter.Ctx, treesitter.Item>
local text_trie = function()
  return trie.new {
    insert_key = function(item)
      return item.text
    end,
    query_key = function(ctx)
      if ctx.keyword_before == "" then
        return nil
      end
      return ctx.keyword_before
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
