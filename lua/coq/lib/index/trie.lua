local handle = require "coq.lib.async.handle"
local search = require "coq.lib.index"

---@class index.TrieSpec<T>
---@field key_item fun(item: T): string
---@field key_ctx fun(ctx: ctx.full): string?

local M = {}

local node_new = function()
  return { children = {}, items = {} }
end

---@param s string
local chars = function(s)
  return string.gmatch(s, ".")
end

---@generic T
---@param spec index.TrieSpec<T>
---@return index.Searcher<T>
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
    for _, item in ipairs(node.items) do
      coroutine.yield(item)
    end
    for _, child in pairs(node.children) do
      dfs_yield(child)
    end
  end

  local trie = {}

  trie.close = function()
    root = node_new()
  end

  trie.insert = function(item)
    table.insert(descend_create(spec.key_item(item)).items, item)
  end

  trie.prune = function(ctx)
    local key = spec.key_ctx(ctx)
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
      local key = spec.key_ctx(ctx)
      if key == nil or key == "" then
        return root
      end
      return descend(key)
    end)()

    local h = handle.new()
    return search.iter(h, function()
      if node ~= nil then
        dfs_yield(node)
      end
    end)
  end

  return trie
end

return M
