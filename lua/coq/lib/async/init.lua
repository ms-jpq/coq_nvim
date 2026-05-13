local cancel = require "coq.lib.cancel"

local M = {}

local threads = setmetatable({}, { __mode = "k" })

M.current_token = function()
  return threads[coroutine.running()]
end

M.future = function(token)
  local thread = coroutine.running()
  assert(thread, "future: must be called inside running coroutine")
  token = token or M.current_token()

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
    if token and token.cancelled then
      return
    end
    if resolved then
      return unpack(resolved)
    end

    return coroutine.yield()
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
  local token = M.current_token()
  if token and token.cancelled then
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
  if token then
    token.watch(fire)
  end

  return await()
end

M.race = function(opts)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local token = opts.cancel or cancel.token(M.current_token())
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

  for idx, fn in ipairs(opts) do
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

M.merge = function(opts)
  local iters = {}
  for _, v in ipairs(opts) do
    table.insert(iters, v)
  end
  local parent = opts.cancel

  return function()
    while #iters > 0 do
      local fns = {}
      for i, iter in ipairs(iters) do
        fns[i] = function()
          return iter()
        end
      end
      if parent then
        fns.cancel = cancel.token(parent)
      end

      local winner, value = M.race(fns)

      if winner == nil then
        return nil
      end

      if value == nil then
        table.remove(iters, winner)
      else
        return value
      end
    end
    return nil
  end
end

return M
