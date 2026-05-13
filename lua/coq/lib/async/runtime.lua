local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"

local M = {}

M.ROOT = handle.new()

local threads = setmetatable({}, { __mode = "k" })

M.bind = function(thread, h)
  threads[thread] = h
end

M.current = function()
  return threads[coroutine.running()] or M.ROOT
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
      local ok, msg = coroutine.resume(thread)
      if not ok then
        error(msg, 0)
      end
    end
  end

  local resolve = function(...)
    finish { ... }
  end

  local await = function(h)
    thread = coroutine.running()
    assert(thread, "await: must be called inside running coroutine")

    h = h or M.current()
    if h.cancelled then
      return
    end
    if not done then
      local unwatch = h.watch(function()
        finish(nil)
      end)
      coroutine.yield()
      unwatch()
    end
    return unpack(values or {})
  end

  return resolve, await
end

M.wrap = function(fn)
  return function(...)
    local resolve, await = M.future()
    local argv = { ... }
    table.insert(argv, resolve)

    fn(unpack(argv))
    return await()
  end
end

M.thunk = function(h, fn)
  if fn == nil then
    fn = h
    h = M.current()
  end
  return function(...)
    assert(coroutine.running() == nil, "thunk: must be called outside a coroutine")
    local argv = { ... }
    local thread = coroutine.create(function()
      fn(unpack(argv))
    end)

    threads[thread] = h

    local ok, ret = coroutine.resume(thread)
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

  local resolve, await = M.future()
  local timer = vim.uv.new_timer()

  return lib.scope(function(defer)
    defer(function()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end)

    defer(h.watch(resolve))

    timer:start(milliseconds, 0, resolve)
    return await()
  end)
end

return M
