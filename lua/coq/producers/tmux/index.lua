local handle = require "coq.lib.async.handle"
local search = require "coq.lib.index"
local trie = require "coq.lib.index.trie"

---@class tmux.Item
---@field word string
---@field pane string

---@return index.Searcher<tmux.Item>
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

---@return index.Searcher<tmux.Item>
local pane_layer = function()
  local panes = {}
  return {
    close = function()
      for _, t in pairs(panes) do
        t.close()
      end
      panes = {}
    end,
    insert = function(item)
      local t = panes[item.pane]
      if t == nil then
        t = word_trie()
        panes[item.pane] = t
      end
      t.insert(item)
    end,
    prune = function(ctx)
      if ctx.pane ~= nil then
        local t = panes[ctx.pane]
        if t then
          t.close()
          panes[ctx.pane] = nil
        end
      else
        for _, t in pairs(panes) do
          t.close()
        end
        panes = {}
      end
    end,
    search = function(ctx)
      local snapshot = panes
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

local instance = pane_layer()

M.search = instance.search
M.insert = instance.insert
M.prune = instance.prune
M.close = instance.close

return M
