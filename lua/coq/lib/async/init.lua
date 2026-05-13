local cancel = require "coq.lib.cancel"

local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.current_token = function()
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

M.race = function(parent, token, fns)
  assert(parent, "race: parent token required")
  if fns == nil then
    fns = token
    token = nil
  end
  token = token or cancel.token(parent)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local resolved = nil

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
    M.run(token, function()
      done(fn())
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

M.thunk = function(token, fn)
  assert(token, "thunk: token required")
  return function(...)
    local argv = { ... }
    local thread = coroutine.create(function()
      fn(unpack(argv))
    end)

    threads[thread] = token

    local ok, ret = coroutine.resume(thread)
    if not ok then
      error(debug.traceback(thread, ret), 0)
    end
  end
end

M.run = function(token, fn)
  M.thunk(token, fn)()
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

return M
