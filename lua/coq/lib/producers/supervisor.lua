local async = require "coq.lib.async"
local deadline = require "coq.lib.async.deadline"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@class producers.Supervisor<C>: producers.Producer<C>
---@field search fun(ctx: C, timeout_ms?: integer): producers.SearchIter

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Supervisor<C>
M.new = function(producers)
  ---@type async.Handle?
  local idle_handle = nil
  local searching = false

  local sup = {}

  sup.bind = function(n)
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

  sup.idle = function(ctx)
    if searching then
      return
    end
    idle_handle = runtime.current()

    local idles = vim
      .iter(producers)
      :map(function(p)
        return function()
          p.idle(ctx)
        end
      end)
      :totable()

    async.all(idles)
  end

  sup.search = function(ctx, timeout_ms)
    if idle_handle then
      idle_handle.cancel()
    end

    local iters = vim
      .iter(producers)
      :map(function(p)
        return p.search(ctx)
      end)
      :totable()

    local m = async.merge(iters)
    searching = true

    local pull = function()
      local _, v = m()
      return v
    end
    local guarded = deadline.new(timeout_ms, pull)

    local close = function()
      searching = false
      m.close()
    end

    local next = function()
      local v = guarded()
      if v == nil then
        searching = false
        runtime.detach(runtime.ROOT, m.close)
      end
      return v
    end

    return setmetatable({ close = close }, { __call = next })
  end

  ---@cast sup producers.Supervisor
  return sup
end

return M
