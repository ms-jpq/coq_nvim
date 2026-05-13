local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.bind = function(thread, h)
  threads[thread] = h
end

M.current = function()
  return threads[coroutine.running()]
end

M.cancelled = function()
  local h = M.current()
  return h ~= nil and h.cancelled
end

M.future = function(h)
  local thread = coroutine.running()
  assert(thread, "future: must be called inside running coroutine")
  h = h or M.current()

  local done = false
  local values

  local finish = function(vals)
    if done then
      return
    end
    done = true
    values = vals
    if coroutine.status(thread) == "suspended" then
      local ok, msg = coroutine.resume(thread)
      if not ok then
        error(msg, 0)
      end
    end
  end

  local resolve = function(...)
    finish { ... }
  end

  local await = function()
    if not done and not (h and h.cancelled) then
      local unwatch = h and h.watch(function()
        finish(nil)
      end)
      coroutine.yield()
      if unwatch then
        unwatch()
      end
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
  assert(h, "thunk: handle required")
  return function(...)
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

M.run = function(h, fn)
  M.thunk(h, fn)()
end

M.sleep = function(milliseconds)
  local h = M.current()
  if h and h.cancelled then
    milliseconds = 0
  end

  local resolve, await = M.future()
  local timer = vim.uv.new_timer()

  local fire = function()
    if timer:is_closing() then
      return
    end
    timer:stop()
    timer:close()
    resolve()
  end

  timer:start(milliseconds, 0, fire)
  if h then
    h.watch(fire)
  end

  return await()
end

return M
