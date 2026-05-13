-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config"
local proto = require "coq.lib.worker.proto"

local worker_body = function(req_fd, resp_fd, bootstrap)
  local raw = vim.mpack.decode(bootstrap)
  package.path = raw.package_path
  package.cpath = raw.package_cpath

  local async = require "coq.lib.async"
  local proto = require "coq.lib.worker.proto"
  local config = require "coq.lib.worker.config"

  local req_pipe, resp_pipe = vim.uv.new_pipe(), vim.uv.new_pipe()
  req_pipe:open(req_fd)
  resp_pipe:open(resp_fd)

  local state, methods = config.parse(raw)

  local send = function(body)
    resp_pipe:write(proto.encode(body))
  end

  local main_pending = {}
  local main_next_id = 0

  local call_main = function(fn, ...)
    main_next_id = main_next_id + 1
    local id = main_next_id
    local argn = select("#", ...)
    local args = { ... }
    local resolve, await = async.future()
    main_pending[id] = resolve
    send {
      kind = "main_call",
      id = id,
      fn_dump = string.dump(fn),
      args = args,
      argn = argn,
    }
    return (function(err, ...)
      if err then
        error(err, 2)
      end
      return ...
    end)(await())
  end

  local worker_mod = require "coq.lib.worker"
  worker_mod.main = call_main

  local handlers = {
    main_response = function(frame)
      local resolve = main_pending[frame.id]
      main_pending[frame.id] = nil
      if not resolve then
        return
      end
      if frame.ok then
        resolve(nil, unpack(frame.values, 1, frame.n))
      else
        resolve(frame.values[1] or "unknown error")
      end
    end,
    request = function(frame)
      local m = methods[frame.method]
      if not m then
        send {
          kind = "response",
          id = frame.id,
          ok = false,
          n = 1,
          values = { "unknown method: " .. tostring(frame.method) },
        }
        return
      end
      local id, args, argn = frame.id, frame.args or {}, frame.argn or 0
      async.run(function()
        local ok, rn, vals = proto.pack(pcall(m, state, unpack(args, 1, argn)))
        send { kind = "response", id = id, ok = ok, n = rn, values = vals }
      end)
    end,
  }

  local buf = ""
  req_pipe:read_start(function(err, data)
    if err or not data then
      req_pipe:close()
      resp_pipe:shutdown(function()
        resp_pipe:close()
      end)
      return
    end
    buf = proto.consume(buf .. data, function(frame)
      handlers[frame.kind](frame)
    end)
  end)

  vim.uv.run()
end

local spawn = function(definition)
  local req_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local resp_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local resp_pipe, req_write = vim.uv.new_pipe(), vim.uv.new_pipe()
  resp_pipe:open(resp_fds.read)
  req_write:open(req_fds.write)

  local pending = {}
  local next_id = 0
  local closed = false

  local handlers = {
    main_call = function(frame)
      local id, fn_dump = frame.id, frame.fn_dump
      local args, argn = frame.args or {}, frame.argn or 0
      vim.schedule(function()
        async.run(function()
          local fn = load(fn_dump)
          local ok, rn, vals = proto.pack(pcall(fn, unpack(args, 1, argn)))
          req_write:write(proto.encode {
            kind = "main_response",
            id = id,
            ok = ok,
            n = rn,
            values = vals,
          })
        end)
      end)
    end,
    response = function(frame)
      local resolve = pending[frame.id]
      pending[frame.id] = nil
      if not resolve then
        return
      end
      if frame.ok then
        resolve(nil, unpack(frame.values, 1, frame.n))
      else
        resolve(frame.values[1] or "unknown error")
      end
    end,
  }

  local buf = ""
  resp_pipe:read_start(function(err, data)
    if err or not data then
      resp_pipe:close()
      for _, resolve in pairs(pending) do
        resolve "worker died"
      end
      pending = {}
      return
    end
    buf = proto.consume(buf .. data, function(frame)
      handlers[frame.kind](frame)
    end)
  end)

  vim.uv.new_thread(worker_body, req_fds.read, resp_fds.write, config.encode(definition))

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    next_id = next_id + 1
    local id = next_id
    pending[id] = cb
    req_write:write(proto.encode {
      kind = "request",
      id = id,
      method = method,
      args = args,
      argn = argn,
    })
  end)

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

  for name in pairs(definition) do
    if name ~= "init" then
      proxy[name] = function(...)
        local argn = select("#", ...)
        return (function(err, ...)
          if err then
            error(err, 3)
          end
          return ...
        end)(call(name, { ... }, argn))
      end
    end
  end

  return proxy
end

return { spawn = spawn }
