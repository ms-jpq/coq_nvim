-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local channel_mod = require "coq.lib.worker.channel"
local config = require "coq.lib.worker.config"
local pending_mod = require "coq.lib.worker.pending"
local proto = require "coq.lib.worker.proto"

local M = {}

M.streaming = function(fn)
  return { streaming = true, fn = fn }
end

local worker_body = function(req_fd, resp_fd, bootstrap)
  local raw = vim.mpack.decode(bootstrap)
  package.path = raw.package_path
  package.cpath = raw.package_cpath

  local async = require "coq.lib.async"
  local proto = require "coq.lib.worker.proto"
  local config = require "coq.lib.worker.config"
  local pending_mod = require "coq.lib.worker.pending"

  local req_pipe, resp_pipe = vim.uv.new_pipe(), vim.uv.new_pipe()
  req_pipe:open(req_fd)
  resp_pipe:open(resp_fd)

  local state, methods = config.parse(raw)

  local send = function(body)
    resp_pipe:write(proto.encode(body))
  end

  local respond = function(id, ok, n, vals)
    send { kind = "response", id = id, ok = ok, n = n, values = vals }
  end

  local main_pending = pending_mod.make()

  local call_main = function(fn, ...)
    local argn = select("#", ...)
    local args = { ... }
    local resolve, await = async.future()
    local id = main_pending.reserve(resolve)
    send {
      kind = "main_call",
      id = id,
      fn_dump = string.dump(fn),
      args = args,
      argn = argn,
    }
    return proto.unwrap(await())
  end

  local iter_resumers = {}

  local make_yield = function(id)
    return function(...)
      local argn = select("#", ...)
      local args = { ... }
      send { kind = "yield", id = id, n = argn, values = args }
      local resolve, await = async.future()
      iter_resumers[id] = resolve
      return await()
    end
  end

  local invoke = function(name, id, args, argn)
    local m = methods[name]
    if not m then
      return false, 1, { "unknown method: " .. tostring(name) }
    end
    if m.kind == "stream" then
      local ok, err = pcall(m.fn, make_yield(id), state, unpack(args, 1, argn))
      iter_resumers[id] = nil
      if ok then
        return true, 0, {}
      end
      return false, 1, { err }
    end
    return proto.pack(pcall(m.fn, state, unpack(args, 1, argn)))
  end

  local resume_iter = function(value)
    return function(frame)
      local r = iter_resumers[frame.id]
      iter_resumers[frame.id] = nil
      if r then
        r(value)
      end
    end
  end

  local worker_mod = require "coq.lib.worker"
  worker_mod.main = call_main

  local handlers = {
    main_response = main_pending.resolve,
    request = function(frame)
      local id = frame.id
      async.run(function()
        respond(id, invoke(frame.method, id, frame.args or {}, frame.argn or 0))
      end)
    end,
    next = resume_iter(true),
    stop = resume_iter(false),
  }

  proto.start_reader(req_pipe, handlers, function()
    resp_pipe:shutdown(function()
      resp_pipe:close()
    end)
  end)

  vim.uv.run()
end

M.spawn = function(definition)
  local req_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local resp_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local resp_pipe, req_write = vim.uv.new_pipe(), vim.uv.new_pipe()
  resp_pipe:open(resp_fds.read)
  req_write:open(req_fds.write)

  local pending = pending_mod.make()
  local closed = false

  local respond_main = function(id, ok, n, vals)
    req_write:write(proto.encode {
      kind = "main_response",
      id = id,
      ok = ok,
      n = n,
      values = vals,
    })
  end

  local handlers = {
    main_call = function(frame)
      local id, fn_dump = frame.id, frame.fn_dump
      local args, argn = frame.args or {}, frame.argn or 0
      vim.schedule(function()
        async.run(function()
          respond_main(id, proto.pack(pcall(load(fn_dump), unpack(args, 1, argn))))
        end)
      end)
    end,
    response = pending.resolve,
    yield = pending.resolve,
  }

  proto.start_reader(resp_pipe, handlers, function()
    pending.drain "worker died"
  end)

  vim.uv.new_thread(worker_body, req_fds.read, resp_fds.write, config.encode(definition))

  local send_request = function(id, method, args, argn)
    req_write:write(proto.encode {
      kind = "request",
      id = id,
      method = method,
      args = args,
      argn = argn,
    })
  end

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    send_request(pending.reserve(cb), method, args, argn)
  end)

  local iter_call = function(method, args, argn)
    if closed then
      error("worker closed", 3)
    end
    local channel = channel_mod.make()
    local id, release = pending.reserve_raw(channel.push)
    send_request(id, method, args, argn)

    local done, first = false, true

    local close = function()
      if done or closed then
        return
      end
      done = true
      req_write:write(proto.encode { kind = "stop", id = id })
      release()
    end

    local next_fn = function()
      if done then
        return nil
      end
      if not first then
        req_write:write(proto.encode { kind = "next", id = id })
      end
      first = false
      local frame = channel.pull()
      if frame.kind == "yield" then
        return unpack(frame.values, 1, frame.n)
      end
      done = true
      release()
      if not frame.ok then
        error(frame.values[1] or "unknown error", 2)
      end
      return nil
    end

    return setmetatable({ close = close }, { __call = next_fn })
  end

  local bind_rpc = function(name)
    return function(...)
      return proto.unwrap(call(name, { ... }, select("#", ...)))
    end
  end

  local bind_stream = function(name)
    return function(...)
      return iter_call(name, { ... }, select("#", ...))
    end
  end

  local proxy = {
    close = function()
      if closed then
        return
      end
      closed = true
      req_write:shutdown(function()
        req_write:close()
      end)
    end,
  }

  for name, decl in pairs(definition) do
    if name ~= "init" then
      local is_stream = type(decl) == "table" and decl.streaming
      proxy[name] = is_stream and bind_stream(name) or bind_rpc(name)
    end
  end

  return proxy
end

return M
