local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@param producers producers.Producer[]
---@return producers.Producer
M.new = function(producers)
  local search_handle, idle_handle = handle.new(), handle.new()
  do
    search_handle.cancel()
    idle_handle.cancel()
  end

  local current_close = lib.noop

  local sup = {}

  sup.search = function(ctx)
    pcall(current_close)

    idle_handle.cancel()
    search_handle = handle.new()
    current_close = search_handle.cancel

    local iters = {}
    for idx, p in ipairs(producers) do
      local row_iter
      iters[idx] = function()
        row_iter = row_iter or p.search(ctx)
        return row_iter()
      end
    end

    local stream = runtime.wrap(function()
      for _, row in async.merge(iters) do
        coroutine.yield(row)
      end
      runtime.current().cancel()
    end, search_handle)

    return setmetatable({ close = search_handle.cancel }, { __call = stream })
  end

  sup.idle = function(ctx)
    if not search_handle.cancelled then
      return
    end
    idle_handle.cancel()
    idle_handle = handle.new()
    runtime.detach(idle_handle, function()
      async.scope(function(n)
        for _, p in ipairs(producers) do
          n.spawn(function()
            p.idle(ctx)
          end)
        end
      end)
    end)
  end

  sup.queue = function(fn, ...)
    local args, n_args = { ... }, select("#", ...)
    async.scope(function(n)
      for _, p in ipairs(producers) do
        n.spawn(function()
          p.queue(fn, unpack(args, 1, n_args))
        end)
      end
    end)
  end

  sup.bind = function(event)
    for _, p in pairs(producers) do
      p.bind(event)
    end
  end

  sup.close = function()
    search_handle.cancel()
    idle_handle.cancel()
    pcall(current_close)
    current_close = lib.noop
    for _, p in ipairs(producers) do
      p.close()
    end
  end

  return sup
end

return M
