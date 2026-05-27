local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@param producers producers.Producer[]
---@return producers.Producer
M.new = function(producers)
  local search_handle, idle_handle = handle.new(), handle.new()

  local interrupt = function()
    search_handle.cancel()
    idle_handle.cancel()
  end
  interrupt()

  local sup = {}

  sup.close = function()
    interrupt()
    for _, p in ipairs(producers) do
      p.close()
    end
  end

  sup.notify = function(_)
    assert(false)
  end

  sup.idle = function(ctx)
    if not search_handle.cancelled then
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
    interrupt()
    search_handle = handle.new()

    local iters = {}
    for idx, p in ipairs(producers) do
      local iter
      iters[idx] = function()
        iter = iter or p.search(ctx)
        return iter()
      end
    end

    local next = runtime.wrap(function()
      return lib.scope(function(defer)
        defer(runtime.current().cancel)
        for _, item in async.merge(iters) do
          coroutine.yield(item)
        end
      end)
    end, search_handle)

    return setmetatable({ close = search_handle.cancel }, { __call = next })
  end

  ---@cast sup producers.Producer
  return sup
end

return M
