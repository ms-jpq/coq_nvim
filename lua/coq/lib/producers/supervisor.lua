local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
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

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Producer<C>
M.new = function(producers)
  local ph = handle.new()
  local search_handle = handle.new()
  ---@type async.Handle[]
  local idle_handles = {}

  local revoke_idles = function()
    for _, h in pairs(idle_handles) do
      h.cancel()
    end
    idle_handles = {}
  end

  local interrupt = function()
    search_handle.cancel()
    revoke_idles()
  end
  interrupt()
  local _ = ph.on_cancel(interrupt)

  ---@type async.Nursery
  local bound_n

  local sup = { max_pulls = math.huge }

  sup.bind = function(n)
    bound_n = n
    local _ = n.handle.on_cancel(ph.cancel)
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

  sup.idle = function(ctx)
    if ph.cancelled or not search_handle.cancelled then
      return
    end
    revoke_idles()

    for _, p in pairs(producers) do
      local h = bound_n.spawn(function()
        p.idle(ctx)
      end)
      table.insert(idle_handles, h)
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

      local iter = async.merge(iters)
      for _, item in iter do
        coroutine.yield(item)
      end
    end)
  end

  ---@cast sup producers.Producer
  return sup
end

return M
