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
    key_item = function(i)
      return i.word
    end,
    key_ctx = function(c)
      if c.line_before == nil then
        return nil
      end
      return string.match(c.line_before, "[%w_]+$")
    end,
  }
end

return search.indexed {
  key_item = function(i)
    return i.pane
  end,
  key_ctx = function(c)
    return c.pane
  end,
  child = word_trie,
}
