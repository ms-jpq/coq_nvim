local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

---@class index.SearchIter: lib.Closable
---@overload fun(): completions.Item?

---@class index.Searchable: lib.Closable
---@field search fun(ctx: ctx.full): index.SearchIter

---@class index.Searcher<T>: index.Searchable
---@field insert fun(item: T)
---@field prune fun(ctx: ctx.full)

---@class index.IndexedSpec<T>
---@field key_item fun(item: T): any
---@field key_ctx fun(ctx: ctx.full): any?
---@field child fun(): index.Searcher<T>

local M = {}

---@type index.Searcher<any>
M.empty = {
  close = lib.noop,
  insert = lib.noop,
  prune = lib.noop,
  search = function()
    return lib.dead_iter
  end,
}

---@param fn fun()
---@param close? fun()
---@return index.SearchIter
M.iter = function(fn, close)
  close = close or lib.noop
  local closed = false
  local bounce = runtime.wrap(fn)

  local it = {
    close = function()
      if closed then
        return
      end
      closed = true
      close()
    end,
  }

  return setmetatable(it, {
    __call = function()
      if closed then
        return nil
      end
      local ok, val = pcall(bounce)
      if not ok then
        lib.report(val)
        it.close()
        return nil
      end
      if val == nil then
        it.close()
      end
      return val
    end,
  })
end

---@generic T
---@param spec index.IndexedSpec<T>
---@return index.Searcher<T>
M.indexed = function(spec)
  local children = {}

  local fanout = function(ctx)
    local current
    return M.iter(function()
      for _, child in pairs(children) do
        current = child.search(ctx)
        for item in current do
          coroutine.yield(item)
        end
        current.close()
        current = nil
      end
    end, function()
      if current then
        current.close()
      end
    end)
  end

  return {
    close = function()
      for _, c in pairs(children) do
        c.close()
      end
      children = {}
    end,

    insert = function(item)
      local k = spec.key_item(item)
      local c = children[k]
      if not c then
        c = spec.child()
        children[k] = c
      end
      c.insert(item)
    end,

    prune = function(ctx)
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
    end,

    search = function(ctx)
      local k = spec.key_ctx(ctx)
      if k == nil then
        return fanout(ctx)
      end
      local c = children[k]
      if not c then
        return lib.dead_iter
      end
      return c.search(ctx)
    end,
  }
end

return M
