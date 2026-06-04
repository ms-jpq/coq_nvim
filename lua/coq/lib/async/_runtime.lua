local cancel = require "coq.lib.async.cancel"
local errs = require "coq.lib.errs"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"

local M = {}

---@type async.Handle
M.ROOT = handle.new()

---@type table<thread, async.Handle>
local threads = lib.weak()

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

M.check_cancellation = function()
  if M.current().cancelled then
    error(cancel.new(), 0)
  end
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
  local vals = nil
  local cbs = {}

  local f = {}

  f.resolve = function(...)
    if vals ~= nil then
      return
    end
    vals = { ... }

    local snapshot = cbs
    cbs = {}
    for _, c in ipairs(snapshot) do
      c(unpack(vals))
    end
  end

  f.once_ready = function(c)
    if vals ~= nil then
      c(unpack(vals))
    else
      table.insert(cbs, c)
    end
  end

  f.await = function(opts)
    if opts and opts.cancel == false then
      return coroutine.yield(setmetatable({ f = f }, AWAIT_EFF))
    end
    M.check_cancellation()
    local h = M.current()
    local ret = { coroutine.yield(setmetatable({ f = f, h = h }, AWAIT_EFF)) }

    if h.cancelled and vals == nil then
      error(cancel.new(), 0)
    end
    return unpack(ret)
  end

  return f
end

---@alias async.Bounce fun(...: any): any

---@param rebind boolean
---@param producer fun(...: any)
---@param on_await fun(bounce: async.Bounce, eff: async.Await)
---@return async.Bounce bounce
---@return thread co
local trampoline = function(rebind, producer, on_await)
  local co = coroutine.create(producer)

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
    if rebind then
      M.bind(co, M.current())
    end
    return dispatch(coroutine.resume(co, ...))
  end

  return bounce, co
end

---@param h async.Handle
---@param fn fun(...)
---@param ... any
M._detach = function(h, fn, ...)
  local bounce, co = trampoline(false, fn, function(bounce, eff)
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
        errs.report(err)
      end
    end

    eff.f.once_ready(resume)
    if not resumed and eff.h then
      unwatch = eff.h.on_cancel(resume)
    end
  end)

  M.bind(co, h)
  return bounce(...)
end

---@generic F: fun(...)
---@param producer F
---@return F
M.wrap = function(producer)
  local bounce = trampoline(true, producer, function(bounce, eff)
    return bounce(coroutine.yield(eff))
  end)
  return bounce
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
