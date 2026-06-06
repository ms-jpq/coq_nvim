local async = require "coq.lib.async"

---@class index.TrieSpec<C, T>
---@field insert_key fun(item: T): string
---@field query_key fun(ctx: C): string?
---@field prefix number
---@field child fun(): index.Searcher<C, T>

local M = {}

local new_node = function()
  return { children = {} }
end

---@param s string?
---@return string?
local norm = function(s)
  return s and string.lower(s)
end

---@generic C, T
---@param spec index.TrieSpec<C, T>
---@return index.Searcher<C, T>
M.new = function(spec)
  local prefix = spec.prefix
  local root = new_node()

  ---@param key string
  local descend = function(key)
    local node = root
    local stop = math.min(prefix, #key)
    for i = 1, stop do
      node = node.children[string.sub(key, i, i)]
      if node == nil then
        return nil
      end
    end
    return node
  end

  ---@param key string
  local descend_create = function(key)
    local node = root
    local stop = math.min(prefix, #key)
    for i = 1, stop do
      local c = string.sub(key, i, i)
      node.children[c] = node.children[c] or new_node()
      node = node.children[c]
    end
    return node
  end

  local query_key = function(ctx)
    return norm(spec.query_key(ctx))
  end

  local function dfs_yield(node, ctx)
    if node.child then
      for hit in node.child.search(ctx) do
        coroutine.yield(hit)
      end
    end
    for _, child_node in pairs(node.children) do
      dfs_yield(child_node, ctx)
    end
  end

  local trie = {}

  trie.insert = function(item)
    local key = norm(spec.insert_key(item)) --[[@as string]]
    local node = descend_create(key)
    node.child = node.child or spec.child()
    node.child.insert(item)
  end

  ---@return boolean
  trie.prune = function(ctx)
    local key = query_key(ctx)
    if key == nil or key == "" then
      root = new_node()
      return true
    end

    local bucket = string.sub(key, 1, math.min(prefix, #key) --[[@as integer]])
    local parent = descend(string.sub(bucket, 1, -2))
    if parent then
      parent.children[string.sub(bucket, -1)] = nil
    end
    return root.child == nil and next(root.children) == nil
  end

  trie.search = function(ctx)
    local node = (function()
      local key = query_key(ctx)
      if key == nil or key == "" then
        return root
      end
      return descend(key)
    end)()

    return async.wrap(function()
      if node ~= nil then
        dfs_yield(node, ctx)
      end
    end)
  end

  return trie
end

return M
