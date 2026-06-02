local async = require "coq.lib.async"
local deadline = require "coq.lib.async.deadline"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Producer<C>
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

  sup.idle = function(settings, ctx)
    if searching then
      return
    end
    idle_handle = runtime.current()

    local idles = vim
      .iter(producers)
      :map(function(p)
        return function()
          p.idle(settings, ctx)
        end
      end)
      :totable()

    async.all(idles)
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
    searching = true

    local close = function()
      searching = false
      m.close()
    end

    local pull = function()
      for _, v in m do
        return v
      end
      return nil
    end

    local timeout_ms = math.floor(settings.limits.completion_auto_timeout * 1000)
    local timed = deadline.new(timeout_ms, pull)

    local next = function()
      local v = timed()
      if v == nil then
        runtime.detach(runtime.ROOT, close)
      end
      return v
    end

    return setmetatable({ close = close }, { __call = next })
  end

  ---@cast sup producers.Producer
  return sup
end

return M
