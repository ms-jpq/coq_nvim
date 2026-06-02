local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class tags.Item: tags.Tag
---@field buf integer

---@class tags.Ctx
---@field buf? integer
---@field keyword_before? string

---@return index.Searcher<tags.Ctx, tags.Item>
local name_trie = function()
  return trie.new {
    insert_key = function(item)
      return item.name
    end,
    query_key = function(ctx)
      if ctx.keyword_before == nil or ctx.keyword_before == "" then
        return nil
      end
      return ctx.keyword_before
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
