-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config"
local pending_mod = require "coq.lib.worker.pending"
local proto = require "coq.lib.worker.proto"

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

  local worker_mod = require "coq.lib.worker"
  worker_mod.main = call_main

  local handlers = {
    main_response = main_pending.resolve,
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

  proto.start_reader(req_pipe, handlers, function()
    resp_pipe:shutdown(function()
      resp_pipe:close()
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

  local pending = pending_mod.make()
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
    response = pending.resolve,
  }

  proto.start_reader(resp_pipe, handlers, function()
    pending.drain "worker died"
  end)

  vim.uv.new_thread(worker_body, req_fds.read, resp_fds.write, config.encode(definition))

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    local id = pending.reserve(cb)
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
        return proto.unwrap(call(name, { ... }, argn))
      end
    end
  end

  return proxy
end

return { spawn = spawn }
