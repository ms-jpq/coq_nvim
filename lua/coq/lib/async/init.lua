local M = {}

M.future = function()
  local thread = coroutine.running()
  assert(thread, "future: must be called inside running coroutine")

  local resolved = nil
  local resolve = function(...)
    if coroutine.status(thread) == "running" then
      resolved = { ... }
    else
      local ok, msg = coroutine.resume(thread, ...)
      if not ok then
        error(msg, 0)
      end
    end
  end

  local await = function()
    if resolved then
      return unpack(resolved)
    end
    return coroutine.yield()
  end

  return resolve, await
end

M.race = function(futures)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local resolved = nil

  for idx, future in pairs(futures) do
    future(function(...)
      if resolved then
        return
      end
      resolved = { idx, ... }
      if coroutine.status(thread) ~= "running" then
        local ok, msg = coroutine.resume(thread, unpack(resolved))
        if not ok then
          error(msg, 0)
        end
      end
    end)
  end

  if resolved then
    return unpack(resolved)
  end
  return coroutine.yield()
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

local thunk = function(fn)
  return function(...)
    local argv = { ... }
    local thread = coroutine.create(function()
      fn(unpack(argv))
    end)

    local ok, ret = coroutine.resume(thread)
    if not ok then
      local tb = debug.traceback(thread, ret)
      error(tb, 0)
    end
  end
end

M.run = function(fn)
  thunk(fn)()
end

M.sleep = function(milliseconds)
  local resolve, await = M.future()
  local timer = vim.uv.new_timer()
  timer:start(milliseconds, 0, function()
    timer:stop()
    timer:close()
    resolve()
  end)
  return await()
end

return setmetatable(M, {
  __call = function(_, fn)
    return thunk(fn)
  end,
})
