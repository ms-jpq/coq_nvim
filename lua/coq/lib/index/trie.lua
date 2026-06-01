local async = require "coq.lib.async"

---@class index.TrieSpec<C, T>
---@field insert_key fun(item: T): string
---@field query_key fun(ctx: C): string?

local M = {}

local node_new = function()
  return { children = {}, item = nil }
end

---@param s string
local chars = function(s)
  return string.gmatch(s, ".")
end

---@generic C, T
---@param spec index.TrieSpec<C, T>
---@return index.Searcher<C, T>
M.new = function(spec)
  local root = node_new()

  ---@param key string
  local descend = function(key)
    local node = root
    for c in chars(key) do
      node = node.children[c]
      if node == nil then
        return nil
      end
    end
    return node
  end

  local descend_create = function(key)
    local node = root
    for c in chars(key) do
      node.children[c] = node.children[c] or node_new()
      node = node.children[c]
    end
    return node
  end

  local function dfs_yield(node)
    if node.item ~= nil then
      coroutine.yield(node.item)
    end
    for _, child in pairs(node.children) do
      dfs_yield(child)
    end
  end

  local trie = {}

  trie.insert = function(item)
    descend_create(spec.insert_key(item)).item = item
  end

  trie.prune = function(ctx)
    local key = spec.query_key(ctx)
    if key == nil or key == "" then
      root = node_new()
      return
    end
    local parent = descend(string.sub(key, 1, -2))
    if parent then
      parent.children[string.sub(key, -1)] = nil
    end
  end

  trie.search = function(ctx)
    local node = (function()
      local key = spec.query_key(ctx)
      if key == nil or key == "" then
        return root
      end
      return descend(key)
    end)()

    return async.wrap(function()
      if node ~= nil then
        dfs_yield(node)
      end
    end)
  end

  return trie
end

return M
