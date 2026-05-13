-- https://github.com/luvit/luv/blob/master/docs/docs.md

local async = require "coq.lib.async"

local _run = async.wrap(function(fn, args, cb)
  local fds = vim.uv.pipe({ nonblock = true }, { nonblock = true })
  local read_pipe = vim.uv.new_pipe(false)
  read_pipe:open(fds.read)

  local buf = {}
  read_pipe:read_start(function(err, data)
    if err then
      read_pipe:close()
      cb(nil, err)
    elseif data then
      table.insert(buf, data)
    else
      read_pipe:close()
      local ok, decoded = pcall(vim.mpack.decode, table.concat(buf))
      if not ok then
        cb(nil, decoded)
      elseif decoded.ok then
        cb(decoded.value)
      else
        cb(nil, decoded.value)
      end
    end
  end)

  vim.uv.new_thread(function(write_fd, fn_dump, ...)
    local write_pipe = vim.uv.new_pipe(false)
    write_pipe:open(write_fd)
    local ok, value = pcall(function(...)
      return load(fn_dump)(...)
    end, ...)
    local payload = vim.mpack.encode { ok = ok, value = value }
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
    local result, err = _run(fn, args)
    if err then
      error(err, 2)
    end
    return result
  end,
}
