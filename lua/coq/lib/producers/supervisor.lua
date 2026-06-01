local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local lib = require "coq.lib"
local mpmc = require "coq.lib.channels.mpmc"

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

---@generic C
---@param producers producers.Producer<C>[]
---@return producers.Producer<C>
M.new = function(producers)
  local dead = false
  ---@type async.Handle[]
  local idle_handles = {}
  ---@type async.Handle?
  local search_h
  local searching = false

  local revoke_idles = function()
    for _, h in pairs(idle_handles) do
      h.cancel()
    end
    idle_handles = {}
  end

  local interrupt = function()
    if search_h then
      search_h.cancel()
    end
    revoke_idles()
  end

  ---@type async.Nursery
  local bound_n

  local sup = { max_pulls = math.huge }

  sup.bind = function(n)
    bound_n = n
    local _ = n.on_cancel(function()
      dead = true
      interrupt()
    end)
    for _, p in pairs(producers) do
      p.bind(n)
    end
  end

  sup.idle = function(ctx)
    if dead or searching then
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
    if dead then
      return lib.noop
    end
    interrupt()

    local chan = mpmc.new()
    local err_holder = { err = nil }
    searching = true
    search_h = bound_n.spawn(function(defer)
      defer(function()
        searching = false
      end)
      defer(chan.close)

      local ok, e = pcall(function()
        local iters = vim
          .iter(producers)
          :map(function(p)
            return capped(p.max_pulls, p.search(ctx))
          end)
          :totable()

        for _, item in async.merge(iters) do
          if not chan.push(item) then
            return
          end
        end
      end)
      if not ok and not cancel.is(e) then
        err_holder.err = e
      end
    end)

    local pull = function()
      local v = chan.pull()
      if v == nil and err_holder.err then
        error(err_holder.err, 0)
      end
      return v
    end

    return setmetatable({ close = search_h.cancel }, { __call = pull })
  end

  ---@cast sup producers.Producer
  return sup
end

return M
