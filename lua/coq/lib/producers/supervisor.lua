local async = require "coq.lib.async"

local M = {}

---@generic T
---@param max integer
---@param iter lib.Iterator<T>
---@return lib.Iterator<T>
local capped = function(max, iter)
  local n = 0
  return function()
    if n >= max then
      return nil
    end
    local v = iter()
    if v == nil then
      return nil
    end
    n = n + 1
    return v
  end
end

---@class producers.Supervisor<C>: producers.Producer<C>
---@field search fun(ctx: C): producers.SearchIter

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Supervisor<C>
M.new = function(producers)
  local sup = { max_pulls = math.huge }

  sup.bind = function(n)
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

  sup.idle = function(ctx)
    async.all(vim
      .iter(producers)
      :map(function(p)
        return function()
          p.idle(ctx)
        end
      end)
      :totable())
  end

  sup.search = function(ctx)
    local iters = vim
      .iter(producers)
      :map(function(p)
        return capped(p.max_pulls, p.search(ctx))
      end)
      :totable()
    local m = async.merge(iters)
    return setmetatable({ close = m.close }, {
      __call = function()
        local _, value = m()
        return value
      end,
    })
  end

  ---@cast sup producers.Supervisor
  return sup
end

return M
