local handle = require "coq.lib.async.handle"

local M = {}

M.handle = handle.new
M.ROOT = handle.ROOT

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

M.race = function(opts)
  local thread = coroutine.running()
  assert(thread, "race: must be called inside running coroutine")
  local h = opts.handle or handle.new(M.current_handle())
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
      h.cancel()
      resume(resolved)
    end
  end

  h.watch(function()
    if resolved then
      return
    end
    resolved = {}
    resume(resolved)
  end)

  for idx, fn in ipairs(opts) do
    local done = finish(idx)
    M.run(h, function()
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
  local parent = opts.handle

  return function()
    while #iters > 0 do
      local race_opts = {}
      for _, iter in ipairs(iters) do
        table.insert(race_opts, function()
          return iter()
        end)
      end
      if parent then
        race_opts.handle = handle.new(parent)
      end

      local winner, value = M.race(race_opts)

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
