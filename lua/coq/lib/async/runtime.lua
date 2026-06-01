local cancel = require "coq.lib.async.cancel"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

local M = {}

---@type async.Handle
M.ROOT = handle.new()

---@type table<thread, async.Handle>
local threads = setmetatable({}, { __mode = "k" })

---@param thread thread
---@param h async.Handle
M.bind = function(thread, h)
  threads[thread] = h
end

---@return async.Handle
M.current = function()
  local thread = coroutine.running()
  assert(thread ~= nil, "current: must be called inside a coroutine")
  return threads[thread] or M.ROOT
end

---@class async.Await
---@field f async.Future
---@field h? async.Handle

local AWAIT_EFF = {}

---@param x any
---@return boolean
local is_await = function(x)
  return type(x) == "table" and getmetatable(x) == AWAIT_EFF
end

---@class async.AwaitOpts
---@field cancel? boolean

---@class async.Future<T>
---@field resolve fun(...: T)
---@field once_ready fun(cb: fun(...: T))
---@field await fun(opts?: async.AwaitOpts): T ...

---@generic T
---@return async.Future<T>
M.future = function()
  local done = false
  local vals = {}
  local cb = nil

  local f = {}

  f.resolve = function(...)
    if done then
      return
    end
    done = true

    vals = { ... }
    if cb then
      local c = cb
      cb = nil
      c(unpack(vals))
    end
  end

  f.once_ready = function(c)
    if done then
      c(unpack(vals))
    else
      assert(cb == nil, "future: a watcher is already registered")
      cb = c
    end
  end

  f.await = function(opts)
    if opts and opts.cancel == false then
      return coroutine.yield(setmetatable({ f = f }, AWAIT_EFF))
    end
    local h = M.current()
    if h.cancelled then
      error(cancel.new(), 0)
    end
    local ret = { coroutine.yield(setmetatable({ f = f, h = h }, AWAIT_EFF)) }
    if h.cancelled then
      error(cancel.new(), 0)
    end
    return unpack(ret)
  end

  return f
end

---@alias async.Bounce fun(...: any): any

---@param producer fun(...: any)
---@param h? async.Handle
---@param on_await fun(bounce: async.Bounce, eff: async.Await)
---@return async.Bounce
local trampoline = function(producer, h, on_await)
  local co = coroutine.create(producer)
  if h then
    M.bind(co, h)
  end

  local bounce
  local dispatch = function(ok, ...)
    if not ok then
      local err = ...
      if cancel.is(err) then
        error(err, 0)
      end
      error(debug.traceback(co, err), 0)
    end
    if coroutine.status(co) == "dead" then
      return nil
    end

    local eff = ...
    if is_await(eff) then
      return on_await(bounce, eff)
    end
    return ...
  end

  bounce = function(...)
    return dispatch(coroutine.resume(co, ...))
  end

  return bounce
end

---@param h async.Handle
---@param fn fun(...)
---@param ... any
M.detach = function(h, fn, ...)
  return trampoline(fn, h, function(bounce, eff)
    local resumed = false
    local unwatch = lib.noop
    local resume = function(...)
      if resumed then
        return
      end
      resumed = true
      unwatch()
      local ok, err = pcall(bounce, ...)
      if not ok and not cancel.is(err) then
        lib.report(err)
      end
    end

    eff.f.once_ready(resume)
    if not resumed and eff.h then
      unwatch = eff.h.on_cancel(resume)
    end
  end)(...)
end

---@generic F: fun(...)
---@param producer F
---@param h? async.Handle
---@return F
M.wrap = function(producer, h)
  return trampoline(producer, h, function(bounce, eff)
    return bounce(coroutine.yield(eff))
  end)
end

---@generic F: fun(...)
---@param fn F
---@return F
M.entry = function(fn)
  return function(...)
    assert(coroutine.running() == nil, "entry: must be called outside a coroutine")
    M.detach(M.ROOT, fn, ...)
  end
end

---@param milliseconds integer
M.sleep = function(milliseconds)
  local f = M.future()
  local watcher, wargv = (function()
    if milliseconds < 0 then
      return vim.uv.new_idle(), { f.resolve }
    else
      vim.uv.update_time()
      return vim.uv.new_timer(), { milliseconds, 0, f.resolve }
    end
  end)()

  return lib.scope(function(defer)
    defer(function()
      if not watcher:is_closing() then
        watcher:stop()
        watcher:close()
      end
    end)

    watcher:start(unpack(wargv))
    return f.await()
  end)
end

return M
