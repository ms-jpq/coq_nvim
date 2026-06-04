local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local deadline = require "coq.lib.async.deadline"

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
    idle_handle = async.current()

    local idles = vim
      .iter(producers)
      :map(function(p)
        return function()
          p.idle(settings, ctx)
        end
      end)
      :totable()

    async.all(idles)
    idle_handle = nil
  end

  sup.search = function(settings, ctx)
    local timeout = ctx.manual and settings.limits.completion_manual_timeout or settings.limits.completion_auto_timeout

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

      local timed = deadline.new(math.floor(timeout * 1000), function()
        local _, v = iter()
        return v
      end)

      defer(close)
      defer(function()
        searching = false
      end)

      for v in timed do
        coroutine.yield(v)
      end
    end)
  end

  return sup
end

return M
