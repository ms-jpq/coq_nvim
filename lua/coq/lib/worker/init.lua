-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local config = require "coq.lib.worker.config"
local errs = require "coq.lib.errs"
local inflight_mod = require "coq.lib.worker.inflight"
local proto = require "coq.lib.worker.proto"
local streaming = require "coq.lib.worker.streaming"

local K = proto.KIND

local M = {}

M.streaming = streaming.wrap

M.spawn = function(definition)
  local req_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local rsp_fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local rsp_pipe, req_write = vim.uv.new_pipe(), vim.uv.new_pipe()
  rsp_pipe:open(rsp_fds.read)
  req_write:open(req_fds.write)

  local inflight = inflight_mod.new()
  local closed = false

  local send = proto.sender(req_write)
  local respond_main = proto.responder(send, K.RESPONSE)

  local handlers = {
    [K.REQUEST] = function(frame)
      local id, fn_dump = frame.id, frame.fn_dump
      local args, argn = frame.args or {}, frame.argn or 0
      local h = async.handle()
      vim.schedule(async.thunk(h, function()
        local fn, err = load(fn_dump)
        if not fn then
          respond_main(id, false, 1, { err or errs.UNKNOWN })
          h.cancel()
          return
        end

        respond_main(id, proto.pack(pcall(fn, unpack(args, 1, argn))))
        h.cancel()
      end))
    end,
    [K.RESPONSE] = inflight.resolve,
    [K.YIELD] = inflight.resolve,
  }

  proto.start_reader(rsp_pipe, handlers, function()
    inflight.drain "worker died"
  end)

  vim.uv.new_thread(function(req_fd, rsp_fd, bootstrap)
    require "coq.lib.worker.run"(req_fd, rsp_fd, vim.mpack.decode(bootstrap))
  end, req_fds.read, rsp_fds.write, config.encode(definition))

  local send_request = function(id, method, args, argn)
    send { kind = K.REQUEST, id = id, method = method, args = args, argn = argn }
  end

  local call = async.wrap(function(method, args, argn, cb)
    if closed then
      return cb "worker closed"
    end
    local id, release
    id, release = inflight.reserve(function(frame)
      release()
      if frame.ok then
        cb(nil, unpack(frame.values, 1, frame.n))
      else
        cb(frame.values[1] or errs.UNKNOWN)
      end
    end)
    send_request(id, method, args, argn)
  end)

  local iter_call = streaming.new(send, inflight, send_request)

  local bind_rpc = function(name)
    return function(...)
      return proto.unwrap(call(name, { ... }, select("#", ...)))
    end
  end

  local bind_stream = function(name)
    return function(...)
      if closed then
        error("worker closed", 2)
      end
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
      proxy[name] = streaming.is(decl) and bind_stream(name) or bind_rpc(name)
    end
  end

  return proxy
end

return M
