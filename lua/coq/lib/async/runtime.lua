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

M.cancelled = function()
  return M.current().cancelled
end

M.future = function()
  local done = false
  local values, thread

  local finish = function(vals)
    if done then
      return
    end
    done = true

    values = vals
    if thread and coroutine.status(thread) == "suspended" then
      local t = thread
      thread = nil

      local ok, msg = coroutine.resume(t)
      if not ok then
        error(msg, 0)
      end
    end
  end

  local f = {}

  f.resolve = function(...)
    finish { ... }
  end

  f.await = function(h)
    local current = coroutine.running()
    assert(current, "await: must be called inside running coroutine")

    h = h or M.current()
    if h.cancelled then
      return
    end

    if not done then
      assert(thread == nil, "future: another coroutine is already awaiting")
      thread = current

      lib.scope(function(defer)
        defer(h.on_cancel(function()
          finish(nil)
        end))

        coroutine.yield()
      end)
    end

    return unpack(values or {})
  end

  return f
end

M.wrap = function(fn)
  return function(...)
    local f = M.future()
    local argv = { ... }
    table.insert(argv, f.resolve)

    fn(unpack(argv))
    return f.await()
  end
end

M.thunk = function(fn)
  return function(...)
    assert(coroutine.running() == nil, "thunk: must be called outside a coroutine")
    local thread = coroutine.create(fn)
    threads[thread] = M.ROOT

    local ok, ret = coroutine.resume(thread, ...)
    if not ok then
      error(debug.traceback(thread, ret), 0)
    end
  end
end

M.sleep = function(milliseconds)
  local h = M.current()
  if h.cancelled then
    milliseconds = 0
  end

  local f = M.future()
  vim.uv.update_time()
  local timer = vim.uv.new_timer()

  return lib.scope(function(defer)
    defer(function()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end)

    defer(h.on_cancel(f.resolve))

    timer:start(milliseconds, 0, f.resolve)
    return f.await()
  end)
end

M.checkpoint = function()
  return M.sleep(0)
end

return M
