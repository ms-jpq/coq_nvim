-- libuv transport for the worker IPC: pipe lifecycle, frame I/O, and the
-- worker-thread bootstrap. Wire framing (encode/decode) is delegated to
-- `wire_proto`; everything libuv-facing lives here.

local proto = require "coq.lib.worker.wire_proto"

local M = {}

-- Open a duplex: a (reader, writer) pair built from two fds. `close` shuts
-- down the writer; the reader auto-closes on EOF inside `start_reader`.
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

-- Allocate a pair of OS pipes wired duplex. Returns the local end (handles
-- already open) and the fds the remote side needs for its `open_duplex`.
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

-- Send-side: a function that encodes a frame body and writes it to the pipe.
M.sender = function(pipe)
  return function(body)
    pipe:write(proto.encode(body))
  end
end

-- Read-side: install a libuv read callback that decodes incoming bytes into
-- frames and routes each to `handlers[frame.kind]`. EOF closes the pipe and
-- fires `on_eof`.
M.start_reader = function(pipe, handlers, on_eof)
  local decode = proto.decoder()

  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      on_eof()
      return
    end
    for frame in decode(data) do
      handlers[frame.kind](frame)
    end
  end)
end

-- Spawn a worker thread that calls `entry_module.run(read_fd, write_fd, decoded)`.
-- `payload` is mpack bytes; the thread bootstrap decodes them before passing
-- to the entry. `remote` is a `{ read_fd, write_fd }` from `duplex_pair`.
M.spawn_worker = function(entry_module, remote, payload)
  vim.uv.new_thread(function(mod, read_fd, write_fd, bytes)
    require(mod).run(read_fd, write_fd, vim.mpack.decode(bytes))
  end, entry_module, remote.read_fd, remote.write_fd, payload)
end

return M
