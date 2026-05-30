local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local search = require "coq.lib.index"

local M = {}

---@param max integer
---@param iter index.SearchIter
---@return index.SearchIter
local capped = function(max, iter)
  local n = 0
  local next = function()
    if n >= max then
      iter.close()
      return nil
    end
    local v = iter()
    if v == nil then
      return nil
    end
    n = n + 1
    return v
  end
  return setmetatable({ close = iter.close }, { __call = next })
end

---@param producers producers.Producer[]
---@return producers.Producer
M.new = function(producers)
  local ph = handle.new()
  local search_handle, idle_handle = handle.new(), handle.new()

  local interrupt = function()
    search_handle.cancel()
    idle_handle.cancel()
  end
  interrupt()
  local _ = ph.on_cancel(interrupt)

  local sup = { max_pulls = math.huge }

  sup.bind = function(n)
    local _ = n.handle.on_cancel(ph.cancel)
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

  sup.idle = function(ctx)
    if ph.cancelled or not search_handle.cancelled then
      return
    end
    idle_handle.cancel()
    idle_handle = handle.new()

    local n = nursery.new(idle_handle)
    for _, p in pairs(producers) do
      n.spawn(function()
        local ok, err = pcall(p.idle, ctx)
        if not ok then
          lib.report(err)
        end
      end)
    end
  end

  sup.search = function(ctx)
    if ph.cancelled then
      return lib.dead_iter
    end
    interrupt()
    search_handle = handle.new()

    return search.iter(search_handle, function()
      local iters = vim
        .iter(producers)
        :map(function(p)
          return capped(p.max_pulls, p.search(ctx))
        end)
        :totable()

      for _, item in async.merge(iters) do
        coroutine.yield(item)
      end
    end)
  end

  ---@cast sup producers.Producer
  return sup
end

return M
