local async = require "coq.lib.async"

---@class index.TrieSpec<C, T>
---@field insert_key fun(item: T): string
---@field query_key fun(ctx: C): string?
---@field prefix? number

local M = {}

local new_node = function()
  return { children = {}, items = {} }
end

---@param s string
local chars = function(s)
  return string.gmatch(s, ".")
end

---@generic C, T
---@param spec index.TrieSpec<C, T>
---@return index.Searcher<C, T>
M.new = function(spec)
  local prefix = spec.prefix or math.huge
  local root = new_node()

  ---@param key string
  local descend = function(key)
    local node, depth = root, 0
    for c in chars(key) do
      if depth >= prefix then
        break
      end
      node = node.children[c]
      if node == nil then
        return nil
      end
      depth = depth + 1
    end
    return node
  end

  ---@param key string
  local descend_create = function(key)
    local node, depth = root, 0
    for c in chars(key) do
      if depth >= prefix then
        break
      end
      node.children[c] = node.children[c] or new_node()
      node = node.children[c]
      depth = depth + 1
    end
    return node
  end

  local function dfs_yield(node)
    for _, item in pairs(node.items) do
      coroutine.yield(item)
    end
    for _, child in pairs(node.children) do
      dfs_yield(child)
    end
  end

  local trie = {}

  trie.insert = function(item)
    local key = spec.insert_key(item)
    descend_create(key).items[key] = item
  end

  trie.prune = function(ctx)
    local key = spec.query_key(ctx)
    if key == nil or key == "" then
      root = new_node()
      return
    end
    local bucket = string.sub(key, 1, math.min(prefix, #key) --[[@as integer]])
    local parent = descend(string.sub(bucket, 1, -2))
    if parent then
      parent.children[string.sub(bucket, -1)] = nil
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
