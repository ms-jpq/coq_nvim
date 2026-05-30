local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class tmux.Item
---@field word string
---@field pane string

---@class tmux.Ctx
---@field pane? string
---@field line_before? string

---@return index.Searcher<tmux.Ctx, tmux.Item>
local word_trie = function()
  return trie.new {
    insert_key = function(item)
      return item.word
    end,
    query_key = function(ctx)
      if ctx.line_before == nil then
        return nil
      end
      return string.match(ctx.line_before, "[%w_]+$")
    end,
  }
end

return search.indexed {
  insert_key = function(item)
    return item.pane
  end,
  query_key = function(ctx)
    return ctx.pane
  end,
  child = word_trie,
}
