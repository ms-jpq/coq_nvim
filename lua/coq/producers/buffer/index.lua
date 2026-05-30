local handle = require "coq.lib.async.handle"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class buffer.Item
---@field word string
---@field buf integer
---@field filetype string

---@return index.Searcher<buffer.Item>
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

---@return index.Searcher<buffer.Item>
local buf_layer = function()
  local bufs = {}
  return {
    close = function()
      for _, t in pairs(bufs) do
        t.close()
      end
      bufs = {}
    end,
    insert = function(item)
      local t = bufs[item.buf]
      if t == nil then
        t = word_trie()
        bufs[item.buf] = t
      end
      t.insert(item)
    end,
    prune = function(ctx)
      if ctx.buf ~= nil then
        local t = bufs[ctx.buf]
        if t then
          t.close()
          bufs[ctx.buf] = nil
        end
      else
        for _, t in pairs(bufs) do
          t.close()
        end
        bufs = {}
      end
    end,
    search = function(ctx)
      local snapshot = bufs
      local cword = ctx.cword
      local h = handle.new()
      return search.iter(h, function()
        for _, t in pairs(snapshot) do
          for item in t.search(ctx) do
            if item.word ~= cword then
              coroutine.yield(item)
            end
          end
        end
      end)
    end,
  }
end

local M = {}

local instance = search.indexed {
  key_item = function(i)
    return i.filetype
  end,
  key_ctx = function(c)
    return c.filetype
  end,
  child = buf_layer,
}

M.search = instance.search
M.insert = instance.insert
M.prune = instance.prune
M.close = instance.close

return M
