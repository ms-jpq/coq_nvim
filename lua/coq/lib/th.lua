-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"

local run = async.wrap(function(fn, args, cb)
  local fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local read_pipe = vim.uv.new_pipe()
  read_pipe:open(fds.read)

  local buf = {}
  read_pipe:read_start(function(err, data)
    if data then
      table.insert(buf, data)
      return
    end
    read_pipe:close()
    if err then
      return cb(err)
    end

    local ok, ret = pcall(vim.mpack.decode, table.concat(buf))
    if not ok then
      return cb(ret)
    end
    if ret.ok then
      cb(nil, unpack(ret.values, 1, ret.n))
    else
      cb(ret.values[1])
    end
  end)

  vim.uv.new_thread(function(write_fd, fn_dump, ...)
    local write_pipe = vim.uv.new_pipe()
    write_pipe:open(write_fd)

    local function pack(ok, ...)
      return ok, select("#", ...), { ... }
    end

    local fn = load(fn_dump)
    local ok, n, vals = pack(pcall(fn, ...))
    local payload = vim.mpack.encode { ok = ok, n = n, values = vals }

    write_pipe:write(payload, function()
      write_pipe:shutdown(function()
        write_pipe:close()
      end)
    end)
    vim.uv.run()
  end, fds.write, string.dump(fn), unpack(args or {}))
end)

return {
  run = function(fn, args)
    return (function(err, ...)
      if err then
        error(err, 3)
      end
      return ...
    end)(run(fn, args))
  end,
}
