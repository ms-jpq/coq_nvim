local async = require "coq.lib.async"
local deadline = require "coq.lib.async.deadline"

local M = {}

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Producer<C>
M.new = function(producers)
  ---@type async.Handle?
  local idle_handle = nil
  ---@type async.Nursery?
  local bound = nil
  local searching = false

  local sup = {}

  sup.bind = function(n)
    bound = n
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

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
    if idle_handle then
      idle_handle.cancel()
    end

    local iters = vim
      .iter(producers)
      :map(function(p)
        return p.search(settings, ctx)
      end)
      :totable()

    local m = async.merge(iters)
    local timed = deadline.new(math.floor(settings.limits.completion_auto_timeout * 1000), function()
      local _, v = m()
      return v
    end)

    searching = true
    local _ = async.current().on_cancel(function()
      searching = false
    end)

    local close = function()
      searching = false
      m.close()
    end

    local next = function()
      for v in timed do
        return v
      end
      -- drained or timed out; on timeout the producers may still be live, so
      -- close off the consumer's path to avoid blocking on merge's join.
      searching = false
      if bound then
        bound.spawn(m.close)
      end
      return nil
    end

    return setmetatable({ close = close }, { __call = next })
  end

  ---@cast sup producers.Producer
  return sup
end

return M
