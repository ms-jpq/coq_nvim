local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.bind = function(thread, h)
  threads[thread] = h
end

M.current = function()
  return threads[coroutine.running()]
end

M.future = function(h)
  local thread = coroutine.running()
  assert(thread, "future: must be called inside running coroutine")
  h = h or M.current()

  local done = false
  local resolved = nil
  local resolve = function(...)
    if done then
      return
    end
    done = true
    if coroutine.status(thread) == "suspended" then
      local ok, msg = coroutine.resume(thread, ...)
      if not ok then
        error(msg, 0)
      end
    else
      resolved = { ... }
    end
  end

  local await = function()
    if resolved then
      return unpack(resolved)
    end
    if h and h.cancelled then
      return
    end

    local active = true
    local unwatch
    if h then
      unwatch = h.watch(function()
        if not active then
          return
        end
        if coroutine.status(thread) == "suspended" then
          local ok, msg = coroutine.resume(thread)
          if not ok then
            error(msg, 0)
          end
        end
      end)
    end

    local ret = { coroutine.yield() }
    active = false
    if unwatch then
      unwatch()
    end
    return unpack(ret)
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
