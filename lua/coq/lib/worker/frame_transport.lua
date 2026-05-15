-- https://github.com/luvit/luv/blob/master/docs/docs.md

local proto = require "coq.lib.worker.wire_proto"

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
  local remote = {
    read_fd = outbound.read,
    write_fd = inbound.write,
  }
  return duplex, remote
end

M.reader = function(pipe)
  local decode = proto.decoder()
  local thread = coroutine.running()

  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      coroutine.resume(thread, nil, err)
    else
      for frame in decode(data) do
        coroutine.resume(thread, frame, nil)
      end
    end
  end)

  return function()
    local frame, err = coroutine.yield()
    if err then
      error(err, 0)
    end
    return frame
  end
end

M.writer = function(pipe)
  return function(body)
    pipe:write(proto.encode(body))
  end
end

M.spawn_worker = function(entry_module, remote, encoded)
  vim.uv.new_thread(function(mod, read_fd, write_fd, bytes)
    require(mod).run(read_fd, write_fd, vim.mpack.decode(bytes))
  end, entry_module, remote.read_fd, remote.write_fd, encoded)
end

return M
