local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class buffer.Item
---@field word string
---@field buf integer
---@field filetype string

---@class buffer.Ctx
---@field buf? integer
---@field filetype? string
---@field line_before? string

---@return index.Searcher<buffer.Ctx, buffer.Item>
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

---@return index.Searcher<buffer.Ctx, buffer.Item>
local buf_layer = function()
  return search.indexed {
    key_item = function(i)
      return i.buf
    end,
    key_ctx = function(c)
      return c.buf
    end,
    child = word_trie,
  }
end

return search.indexed {
  key_item = function(i)
    return i.filetype
  end,
  key_ctx = function(c)
    return c.filetype
  end,
  child = buf_layer,
}
