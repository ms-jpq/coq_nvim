-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local proto = require "coq.lib.worker.wire_proto"
local runtime = require "coq.lib.async.runtime"

local M = {}

M.open_duplex = function(read_fd, write_fd)
  local duplex = {}
  duplex.reader, duplex.writer = vim.uv.new_pipe(), vim.uv.new_pipe()
  duplex.reader:open(read_fd)
  duplex.writer:open(write_fd)

  duplex.close = function()
    duplex.writer:shutdown(function()
      duplex.writer:close()
    end)
  end
  return duplex
end

M.duplex_pair = function()
  local inbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local outbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })

  local duplex = M.open_duplex(inbound.read, outbound.write)
  local remote = { read_fd = outbound.read, write_fd = inbound.write }
  return duplex, remote
end

local read_once = async.awaitify(function(pipe, cb)
  pipe:read_start(function(err, bytes)
    pipe:read_stop()
    if err or not bytes then
      pipe:close()
    end
    cb(err, bytes)
  end)
end)

M.reader = function(pipe)
  local decoder = proto.decoder()

  return runtime.wrap(function()
    while true do
      local err, bytes = read_once(pipe)
      if err then
        error(err, 0)
      end
      if not bytes then
        return
      end
      for frame in decoder(bytes) do
        coroutine.yield(frame)
      end
    end
  end)
end

M.writer = function(pipe)
  return function(body)
    local f = runtime.future()
    pipe:write(proto.encode(body), function(err)
      f.resolve(err)
    end)
    local err = f.await()
    if err then
      error(err, 0)
    end
  end
end

M.spawn_worker = function(fn, ...)
  local dumped = string.dump(fn)
  vim.uv.new_thread(function(d, ...)
    load(d)(...)
  end, dumped, ...)
end

return M
