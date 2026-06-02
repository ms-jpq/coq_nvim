local async = require "coq.lib.async"
local lib = require "coq.lib"

---@class index.Searchable<C, T>
---@field search fun(ctx: C): lib.Iterator<T>

---@class index.Searcher<C, T>: index.Searchable<C, T>
---@field insert fun(item: T)
---@field prune fun(ctx: C): boolean

---@class index.IndexedSpec<C, T>
---@field insert_key fun(item: T): any
---@field query_key fun(ctx: C): any?
---@field child fun(): index.Searcher<C, T>

local M = {}

---@type index.Searcher<any, any>
M.empty = {
  insert = lib.noop,
  prune = function()
    return true
  end,
  search = function()
    return lib.noop
  end,
}

---@generic C, T
---@param spec index.IndexedSpec<C, T>
---@return index.Searcher<C, T>
M.indexed = function(spec)
  local children = {}

  local fanout = function(ctx)
    return async.wrap(function()
      for _, child in pairs(children) do
        for item in child.search(ctx) do
          coroutine.yield(item)
        end
      end
    end)
  end

  local index = {}

  index.prune = function(ctx)
    local k = spec.query_key(ctx)
    if k == nil then
      for ck, c in pairs(children) do
        if c.prune(ctx) then
          children[ck] = nil
        end
      end
    else
      local c = children[k]
      if c and c.prune(ctx) then
        children[k] = nil
      end
    end
    return next(children) == nil
  end

  index.insert = function(item)
    local k = spec.insert_key(item)
    local c = children[k]
    if not c then
      c = spec.child()
      children[k] = c
    end
    c.insert(item)
  end

  index.search = function(ctx)
    local k = spec.query_key(ctx)
    if k == nil then
      return fanout(ctx)
    end
    local c = children[k]
    if not c then
      return lib.noop
    end
    return c.search(ctx)
  end

  return index
end

return M
