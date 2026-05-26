local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

local M = {}

M.ROOT = handle.new()

local threads = setmetatable({}, { __mode = "k" })

M.bind = function(thread, h)
  threads[thread] = h
end

M.current = function()
  local thread = coroutine.running()
  assert(thread ~= nil, "current: must be called inside a coroutine")
  return threads[thread] or M.ROOT
end

local AWAIT_EFF = {}

local is_await = function(x)
  return type(x) == "table" and getmetatable(x) == AWAIT_EFF
end

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

  f.await = function(h)
    return coroutine.yield(setmetatable({ f = f, h = h }, AWAIT_EFF))
  end

  return f
end

M.drive = function(h, fn)
  local co = coroutine.create(fn)
  M.bind(co, h)

  local step
  step = function(...)
    local ok, eff = coroutine.resume(co, ...)
    if not ok then
      error(eff, 0)
    end
    if coroutine.status(co) == "dead" then
      return
    end

    if is_await(eff) then
      local woke = false
      local unwatch = lib.noop
      local wake = function(...)
        if woke then
          return
        end
        woke = true
        unwatch()
        return step(...)
      end

      eff.f.once_ready(wake)
      if not woke and eff.h then
        unwatch = eff.h.on_cancel(wake)
      end
      return
    end

    error("bare yield outside a stream", 0)
  end

  step()
end

M.thunk = function(fn)
  return function(...)
    assert(coroutine.running() == nil, "thunk: must be called outside a coroutine")
    local args = { ... }
    M.drive(M.ROOT, function()
      return fn(unpack(args))
    end)
  end
end

M.sleep = function(milliseconds, h)
  if h == nil then
    h = M.current()
  elseif h == false then
    h = nil
  end

  if h and h.cancelled then
    return
  end

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
    return f.await(h)
  end)
end

M.preemptible = function(fn)
  local h
  return function()
    h = h or handle.new(M.current())
    if h.cancelled then
      return nil
    end

    local f = M.future()

    return lib.scope(function(defer)
      defer(h.on_cancel(f.resolve))

      M.drive(h, function()
        f.resolve(xpcall(fn, debug.traceback))
      end)

      local ok, ret = f.await(h)
      if ok == nil then
        return nil
      end
      if not ok then
        error(ret, 0)
      end
      return ret
    end)
  end
end

M.stream = function(producer, h)
  local co = coroutine.create(producer)
  if h then
    M.bind(co, h)
  end

  local pull
  pull = function(...)
    local go = function(ok, ...)
      if not ok then
        error(debug.traceback(co, (...)), 0)
      end
      if coroutine.status(co) == "dead" then
        return nil
      end

      local eff = ...
      if is_await(eff) then
        return pull(coroutine.yield(eff))
      end
      return ...
    end
    return go(coroutine.resume(co, ...))
  end

  return pull
end

return M
