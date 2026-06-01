local lib = require "coq.lib"
local mpmc = require "coq.lib.channels.mpmc"
local nursery = require "coq.lib.async.nursery"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.future = runtime.future
M.sleep = runtime.sleep
M.wrap = runtime.wrap
M.entry = runtime.entry

---@generic T
---@param body fun(nursery: async.Nursery, defer: fun(cleanup: fun())): T?
---@return T
M.scope = function(body)
  local n = nursery.new()
  return lib.scope(function(defer)
    local rets = {}
    n.spawn(function()
      rets = { body(n, defer) }
    end)
    n.join()
    return unpack(rets)
  end)
end

---@overload fun<A, B>(fns: [(fun(): A), (fun(): B)]): [A, B]
---@overload fun<A, B, C>(fns: [(fun(): A), (fun(): B), (fun(): C)]): [A, B, C]
---@overload fun<A, B, C, D>(fns: [(fun(): A), (fun(): B), (fun(): C), (fun(): D)]): [A, B, C, D]
---@param fns (fun(): any)[]
---@return any[]
M.all = function(fns)
  local results = {}
  M.scope(function(n)
    for idx, fn in pairs(fns) do
      n.spawn(function()
        results[idx] = fn()
      end)
    end
  end)
  return results
end

---@generic T
---@param fns (fun(): T?)[]
---@return integer?, T?
M.race = function(fns)
  if #fns == 0 then
    return
  end

  local f = runtime.future()

  return M.scope(function(n, defer)
    defer(n.handle.on_cancel(f.resolve))

    for idx, fn in pairs(fns) do
      n.spawn(function()
        f.resolve(idx, fn())
      end)
    end

    local finish = function(...)
      n.handle.cancel()
      return ...
    end
    return finish(f.await())
  end)
end

---@class async.MergeIter<T>: lib.Closable
---@overload fun(): integer, T

---@generic T
---@param iters (fun(): T)[]
---@return async.MergeIter<T>
M.merge = function(iters)
  local n = nursery.new()
  local chan = mpmc.new(1)
  local _ = n.handle.on_cancel(chan.close)
  local active = #iters

  if active == 0 then
    n.handle.cancel()
  end

  for idx, iter in pairs(iters) do
    n.spawn(function()
      for v in iter do
        chan.push(idx, v)
      end

      active = active - 1
      if active == 0 then
        n.handle.cancel()
      end
    end)
  end

  local close = function()
    n.handle.cancel()
    n.join()
  end

  local next = function()
    local idx, value = chan.pull()
    if idx == nil then
      return close()
    end
    return idx, value
  end

  return setmetatable({ close = close }, { __call = next })
end

---@param fn function
---@return function
M.awaitify = function(fn)
  return function(...)
    local f = runtime.future()
    local argv = { ... }
    table.insert(argv, f.resolve)

    fn(unpack(argv))
    return f.await()
  end
end

return M
