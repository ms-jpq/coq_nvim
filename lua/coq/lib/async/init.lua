local cancel = require "coq.lib.cancel"

local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.cancellation = function()
  return threads[coroutine.running()]
end

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

M.race = function(fns, parent)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local resolved = nil
  local token = cancel.token(parent)

  local resume = function(values)
    if coroutine.status(thread) == "suspended" then
      local ok, msg = coroutine.resume(thread, unpack(values))
      if not ok then
        error(msg, 0)
      end
    end
  end

  local finish = function(idx)
    return function(...)
      if resolved then
        return
      end
      resolved = { idx, ... }
      token.cancel()
      resume(resolved)
    end
  end

  token.watch(function()
    if resolved then
      return
    end
    resolved = {}
    resume(resolved)
  end)

  for idx, fn in pairs(fns) do
    local done = finish(idx)
    M.run(function()
      done(fn())
    end, token)
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

local thunk = function(fn, token)
  return function(...)
    local parent = threads[coroutine.running()]
    if token then
      if parent then
        parent.watch(token)
      end
    else
      token = parent
    end

    local argv = { ... }
    local thread = coroutine.create(function()
      fn(unpack(argv))
    end)

    threads[thread] = token

    local ok, ret = coroutine.resume(thread)
    if not ok then
      local tb = debug.traceback(thread, ret)
      error(tb, 0)
    end
  end
end

M.run = function(fn, token)
  thunk(fn, token)()
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
  __call = function(_, fn, token)
    return thunk(fn, token)
  end,
})
