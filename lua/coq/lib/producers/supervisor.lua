local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"

local M = {}

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Producer<C>
M.new = function(producers)
  ---@type async.Handle?
  local idle_handle = nil
  local searching = false

  ---@diagnostic disable-next-line: missing-fields
  local sup = {} ---@type producers.Producer

  sup.idle = function(settings, ctx)
    if searching then
      return
    end
    lib.scope(function(defer)
      idle_handle = async.current()
      defer(function()
        idle_handle = nil
      end)

      local idles = vim
        .iter(producers)
        :map(function(p)
          return function()
            p.idle(settings, ctx)
          end
        end)
        :totable()

      async.all(idles)
    end)
  end

  sup.search = function(settings, ctx)
    if idle_handle then
      idle_handle.cancel()
    end
    searching = true
    local _ = async.current().on_cancel(function()
      searching = false
    end)

    return closable.iter(function(defer)
      local iters = {}
      for _, p in pairs(producers) do
        local c, i = p.search(settings, ctx)
        defer(c)
        table.insert(iters, i)
      end

      local close, iter = async.merge(iters)
      defer(close)
      defer(function()
        searching = false
      end)

      for _, v in iter do
        coroutine.yield(v)
      end
    end)
  end

  return sup
end

return M
