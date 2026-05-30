local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class index.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@class index.Searchable<C>: lib.Closable
---@field search fun(ctx: C): index.SearchIter

---@class index.Searcher<C, T>: index.Searchable<C>
---@field insert fun(item: T)
---@field prune fun(ctx: C)

---@class index.IndexedSpec<C, T>
---@field key_item fun(item: T): any
---@field key_ctx fun(ctx: C): any?
---@field child fun(): index.Searcher<C, T>

local M = {}

---@type index.Searcher<any, any>
M.empty = {
  close = lib.noop,
  insert = lib.noop,
  prune = lib.noop,
  search = function()
    return lib.dead_iter
  end,
}

---@param h async.Handle
---@param fn fun()
---@return index.SearchIter
M.iter = function(h, fn)
  local bounce = async.wrap(fn, h)

  local next = function()
    if h.cancelled then
      return nil
    end
    local ok, val = pcall(bounce)
    if not ok then
      h.cancel()
      error(val, 0)
    end
    if h.cancelled or val == nil then
      h.cancel()
      return nil
    end
    return val
  end

  return setmetatable({ close = h.cancel }, { __call = next })
end

---@generic C, T
---@param spec index.IndexedSpec<C, T>
---@return index.Searcher<C, T>
M.indexed = function(spec)
  local children = {}

  local fanout = function(ctx)
    local h = handle.new(runtime.current())
    return M.iter(h, function()
      for _, child in pairs(children) do
        lib.scope(function(defer)
          local iter = child.search(ctx)
          defer(iter.close)
          defer(h.on_cancel(iter.close))
          for item in iter do
            coroutine.yield(item)
          end
        end)
      end
    end)
  end

  local index = {}

  index.close = function()
    for _, c in pairs(children) do
      c.close()
    end
    children = {}
  end

  index.prune = function(ctx)
    local k = spec.key_ctx(ctx)
    if k == nil then
      for _, c in pairs(children) do
        c.prune(ctx)
      end
    else
      local c = children[k]
      if c then
        c.prune(ctx)
      end
    end
  end

  index.insert = function(item)
    local k = spec.key_item(item)
    local c = children[k]
    if not c then
      c = spec.child()
      children[k] = c
    end
    c.insert(item)
  end

  index.search = function(ctx)
    local k = spec.key_ctx(ctx)
    if k == nil then
      return fanout(ctx)
    end
    local c = children[k]
    if not c then
      return lib.dead_iter
    end
    return c.search(ctx)
  end

  return index
end

return M
