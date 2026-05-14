-- libuv transport for the worker IPC: pipe lifecycle, frame I/O, and the
-- worker-thread bootstrap. Wire framing (encode/decode) is delegated to
-- `wire_proto`; everything libuv-facing lives here.

local async = require "coq.lib.async"
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

-- Read-side: a coroutine-yielding iterator over inbound frames. The libuv
-- read callback drops decoded frames into a queue and resumes the consumer.
-- EOF closes the pipe and ends iteration; the consumer's post-loop block
-- runs the on-EOF logic.
--
-- Must be consumed from inside a coroutine (e.g. via `async.thunk`).
M.frames = function(pipe)
  local decode = proto.decoder()
  local pending = {}
  local eof = false
  local waiter = nil

  local wake = function()
    local f = waiter

    waiter = nil
    if f then
      f.resolve()
    end
  end

  pipe:read_start(function(err, data)
    if err or not data then
      pipe:close()
      eof = true
    else
      for frame in decode(data) do
        table.insert(pending, frame)
      end
    end
    wake()
  end)

  return function()
    while #pending == 0 and not eof do
      waiter = async.future()
      waiter.await()
    end
    return table.remove(pending, 1)
  end
end

-- Send-side: a function that encodes a frame body and writes it to the pipe.
M.sender = function(pipe)
  return function(body)
    pipe:write(proto.encode(body))
  end
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
