local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.current_handle = function()
  return threads[coroutine.running()]
end

M.future = function(h)
  local thread = coroutine.running()
  assert(thread, "future: must be called inside running coroutine")
  h = h or M.current_handle()

  local resolved = nil
  local resolve = function(...)
    if coroutine.status(thread) == "running" then
      resolved = { ... }
    elseif coroutine.status(thread) == "suspended" then
      local ok, msg = coroutine.resume(thread, ...)
      if not ok then
        error(msg, 0)
      end
    end
  end

  local await = function()
    if h and h.cancelled then
      return
    end
    if resolved then
      return unpack(resolved)
    end

    local unwatch
    if h then
      unwatch = h.watch(function()
        if coroutine.status(thread) == "suspended" then
          local ok, msg = coroutine.resume(thread)
          if not ok then
            error(msg, 0)
          end
        end
      end)
    end

    local ret = { coroutine.yield() }
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
    local thread
    thread = coroutine.create(function()
      local ok, err = xpcall(function()
        fn(unpack(argv))
      end, debug.traceback)
      h.deregister(thread)
      if not ok then
        error(err, 0)
      end
    end)

    threads[thread] = h
    h.register(thread)

    local ok, ret = coroutine.resume(thread)
    if not ok then
      error(ret, 0)
    end
  end
end

M.run = function(h, fn)
  M.thunk(h, fn)()
end

M.join = function(h)
  assert(h, "join: handle required")
  local resolve, await = M.future()
  h.on_empty(resolve)
  await()
end

M.sleep = function(milliseconds)
  local h = M.current_handle()
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
