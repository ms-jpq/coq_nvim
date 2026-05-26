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

local AWAIT = {}

local is_await = function(x)
  return type(x) == "table" and getmetatable(x) == AWAIT
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
    return coroutine.yield(setmetatable({ f = f, h = h }, AWAIT))
  end

  return f
end

M.drive = function(co, opts)
  local on_error = opts.on_error or function(e)
    error(e, 0)
  end
  local on_done = opts.on_done or lib.noop
  local on_emit = opts.on_emit

  local step
  step = function(...)
    local ok, eff = coroutine.resume(co, ...)
    if not ok then
      return on_error(eff)
    end
    if coroutine.status(co) == "dead" then
      return on_done(eff)
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

    if on_emit then
      return on_emit(eff, step)
    end

    return on_error "emit (bare yield) outside a stream"
  end

  return step
end

M.thunk = function(fn)
  return function(...)
    assert(coroutine.running() == nil, "thunk: must be called outside a coroutine")
    local thread = coroutine.create(fn)
    threads[thread] = M.ROOT
    M.drive(thread, {})(...)
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
    local thread = coroutine.create(function()
      f.resolve(xpcall(fn, debug.traceback))
    end)

    return lib.scope(function(defer)
      defer(h.on_cancel(f.resolve))

      M.bind(thread, h)
      M.drive(thread, {})()

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

-- Bridge a push-driven producer to a pull-iterator consumer. The producer
-- coroutine interleaves emit(v) and await(...) on a single thread; the
-- returned iterator yields each emit. If `h` is given, the producer is bound
-- to it (its awaits become cancellable) AND the consumer's await is too --
-- closing the iterator cancels both sides.
M.stream = function(producer, h)
  local ready = M.future()
  local cont
  local value = nil
  local alive = true

  local thread = coroutine.create(producer)
  if h then
    threads[thread] = h
  end

  M.drive(thread, {
    on_emit = function(v, k)
      value, cont = v, k
      ready.resolve()
    end,
    on_done = function()
      alive = false
      ready.resolve()
    end,
    on_error = function(err)
      alive = false
      value = { __err = err }
      ready.resolve()
    end,
  })()

  if h then
    h.on_cancel(function()
      local k = cont
      cont = nil
      if k then
        k(true)
      end
    end)
  end

  return function()
    ready.await(h)
    if h and h.cancelled then
      return nil
    end
    if type(value) == "table" and value.__err then
      error(value.__err, 0)
    end
    if not alive then
      return nil
    end
    local v = value
    ready = M.future()
    local k = cont
    cont = nil
    if k then
      k(true)
    end
    return v
  end
end

return M
