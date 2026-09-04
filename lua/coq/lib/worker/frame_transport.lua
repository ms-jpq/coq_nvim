-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"
local proto = require "coq.lib.worker.wire_proto"

---@class worker.Duplex: lib.Closable
---@field reader uv.uv_pipe_t
---@field writer uv.uv_pipe_t

---@class worker.RemoteEnd
---@field read_fd integer
---@field write_fd integer

local M = {}

---@param read_fd integer
---@param write_fd integer
---@return worker.Duplex
M.open_duplex = function(read_fd, write_fd)
  ---@diagnostic disable-next-line: missing-fields
  local duplex = {} ---@type worker.Duplex

  duplex.reader, duplex.writer = assert(vim.uv.new_pipe()), assert(vim.uv.new_pipe())
  duplex.reader:open(read_fd)
  duplex.writer:open(write_fd)

  local closed = async.future()
  local state = closable.new(function()
    if duplex.writer:is_closing() then
      closed.resolve()
      return
    end
    duplex.writer:shutdown(function()
      if not duplex.writer:is_closing() then
        duplex.writer:close(closed.resolve)
      else
        closed.resolve()
      end
    end)
  end)

  duplex.close = function()
    state.close()
    closed.await { cancel = false }
  end

  return duplex
end

---@return worker.Duplex, worker.RemoteEnd
M.duplex_pair = function()
  local inbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local outbound = vim.uv.pipe({ nonblock = true }, { nonblock = true })

  assert(inbound and outbound)
  local duplex = M.open_duplex(inbound.read, outbound.write)
  local remote = { read_fd = outbound.read, write_fd = inbound.write }
  return duplex, remote
end

---@param pipe uv.uv_pipe_t
---@return string?, string?
local read_once = function(pipe)
  return lib.scope(function(defer)
    local fut = async.future()
    local result = nil

    defer(function()
      local err, bytes = unpack(result or {}, 1, 2)
      if not pipe:is_closing() then
        pipe:read_stop()
        if result == nil or err or bytes == nil then
          local f = async.future()
          pipe:close(f.resolve)
          f.await { cancel = false }
        end
      end
    end)

    pipe:read_start(function(err, bytes)
      result = { err, bytes }
      fut.resolve()
    end)
    fut.await()

    if result then
      return unpack(result, 1, 2)
    end
  end)
end

---@param pipe uv.uv_pipe_t
---@return fun(): table?
M.reader = function(pipe)
  local decoder = proto.decoder()

  return async.wrap(function()
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

---@nodiscard
---@param pipe uv.uv_pipe_t
---@return fun(body: table): boolean
M.writer = function(pipe)
  return function(body)
    if pipe:is_closing() then
      return false
    end
    local f = async.future()
    pipe:write(proto.encode(body), function(err)
      f.resolve(err)
    end)
    local err = f.await { cancel = false }
    if err then
      error(err, 0)
    end
    return true
  end
end

---@param fn fun(...: any)
---@param ... any
M.spawn_worker = function(fn, ...)
  local dumped = string.dump(fn)
  local args, n_args = { ... }, select("#", ...)
  local spawned = async.future()

  vim.schedule(function()
    assert(coroutine.running() == nil)
    local ok, handle, err = pcall(vim.uv.new_thread, {}, function(d, ...)
      load(d)(...)
    end, dumped, unpack(args, 1, n_args))
    spawned.resolve(ok and handle or nil, ok and err or handle)
  end)

  local handle, err = spawned.await { cancel = false }
  if not handle then
    error(err, 0)
  end
end

return M
