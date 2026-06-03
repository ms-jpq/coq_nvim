local async = require "coq.lib.async"
local closable = require "coq.lib.closable"

local M = {}

---@type fun()
M.scheduled = async.awaitify(vim.schedule)

---@class atools.SpawnOpts
---@field stdin? string

---@class atools.SpawnResult
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string

---@param argv string[]
---@param opts? atools.SpawnOpts
---@return atools.SpawnResult?
M.spawn = function(argv, opts)
  opts = opts or {}

  return async.scope(function(n, defer)
    local stdin_pipe = opts.stdin ~= nil and assert(vim.uv.new_pipe()) or nil
    local stdout_pipe = assert(vim.uv.new_pipe())
    local stderr_pipe = assert(vim.uv.new_pipe())

    local close = function(h)
      if not h:is_closing() then
        h:close()
      end
    end
    for _, p in pairs { stdout_pipe, stderr_pipe, stdin_pipe } do
      defer(function()
        close(p)
      end)
    end

    local stdin_f, exit_f, stdout_f, stderr_f = async.future(), async.future(), async.future(), async.future()

    local handle = assert(vim.uv.spawn(argv[1], {
      args = vim.list_slice(argv, 2),
      stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
    }, function(code, signal)
      exit_f.resolve(true, { code = code, signal = signal })
    end))

    defer(function()
      close(handle)
    end)
    defer(n.on_cancel(function()
      if not handle:is_closing() then
        handle:kill "sigterm"
      end
    end))

    do
      local stdin_done = function(err)
        stdin_f.resolve(err == nil, err)
      end
      if stdin_pipe ~= nil then
        stdin_pipe:write(opts.stdin, function(err)
          if err ~= nil then
            stdin_done(err)
          else
            stdin_pipe:shutdown(stdin_done)
          end
        end)
      else
        stdin_done()
      end
    end

    local read = function(pipe, f)
      local chunks = {}
      pipe:read_start(function(err, data)
        if err ~= nil then
          pipe:read_stop()
          f.resolve(false, err)
        elseif data == nil then
          pipe:read_stop()
          f.resolve(true, table.concat(chunks))
        else
          table.insert(chunks, data)
        end
      end)
    end
    read(stdout_pipe, stdout_f)
    read(stderr_pipe, stderr_f)

    local await = function(f)
      return function()
        local ok, value = f.await()
        if not ok then
          error(value, 0)
        end
        return value
      end
    end

    local _, proc, stdout, stderr = unpack(async.all {
      await(stdin_f),
      await(exit_f),
      await(stdout_f),
      await(stderr_f),
    })
    if not proc then
      return nil
    end
    proc.stdout = stdout
    proc.stderr = stderr
    return proc
  end)
end

---@type fun(path: string): uv.error_name?, uv.luv_dir_t?
local fs_opendir = async.awaitify(vim.uv.fs_opendir)
---@type fun(dir: uv.luv_dir_t): uv.error_name?, boolean?
local fs_closedir = async.awaitify(vim.uv.fs_closedir)
---@type fun(dir: uv.luv_dir_t): uv.error_name?, { name: string, type: string }[]?
local fs_readdir = async.awaitify(vim.uv.fs_readdir)

---@type fun(path: string, flags: string|integer, mode: integer): uv.error_name?, integer?
local fs_open = async.awaitify(vim.uv.fs_open)
---@type fun(fd: integer): uv.error_name?
local fs_close = async.awaitify(vim.uv.fs_close)
---@type fun(fd: integer, size: integer, offset: integer): uv.error_name?, string?
local fs_read = async.awaitify(vim.uv.fs_read)
---@type fun(fd: integer): uv.error_name?, uv.fs_stat.result?
local fs_fstat = async.awaitify(vim.uv.fs_fstat)

M.fs = {
  ---@type fun(path: string): uv.error_name?, uv.fs_stat.result?
  stat = async.awaitify(vim.uv.fs_stat),
}

---@param path string
---@return boolean
M.fs.is_dir = function(path)
  local err, st = M.fs.stat(path)
  return (not err and st and st.type == "directory") or false
end

---@param path string
---@return fun() close
---@return fun(): string?, string? iter
M.fs.scandir = function(path)
  return closable.iter(function(defer)
    local err, dir = fs_opendir(path)
    if err ~= nil or dir == nil then
      return
    end
    defer(function()
      fs_closedir(dir)
    end)

    while true do
      local e, entries = fs_readdir(dir)
      if e ~= nil or entries == nil or #entries == 0 then
        return
      end
      for _, entry in pairs(entries) do
        coroutine.yield(entry.name, entry.type)
      end
    end
  end)
end

---@param path string
---@return fun() close
---@return lib.Iterator<string> iter
M.fs.scanfile = function(path)
  return closable.iter(function(defer)
    local e1, fd = fs_open(path, "r", 438)
    if e1 ~= nil or fd == nil then
      return
    end
    defer(function()
      fs_close(fd)
    end)

    local e2, st = fs_fstat(fd)
    if e2 ~= nil or st == nil then
      return
    end

    while true do
      local e3, data = fs_read(fd, st.blksize, -1)
      if e3 ~= nil or data == nil or #data == 0 then
        return
      end
      coroutine.yield(data)
    end
  end)
end

M.ui = {
  ---@generic T
  ---@type fun(items: T[], opts: table): T?, integer?
  select = vim.ui and async.awaitify(vim.ui.select),
}

return M
