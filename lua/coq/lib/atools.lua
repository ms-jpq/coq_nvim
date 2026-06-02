local async = require "coq.lib.async"
local lib = require "coq.lib"
local txt = require "coq.lib.text"

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

M.fs = {
  ---@type fun(path: string, flags: string|integer, mode: integer): string?, integer?
  open = async.awaitify(vim.uv.fs_open),
  ---@type fun(fd: integer): string?
  close = async.awaitify(vim.uv.fs_close),
  ---@type fun(fd: integer, size: integer, offset: integer): string?, string?
  read = async.awaitify(vim.uv.fs_read),
  ---@type fun(fd: integer): string?, { size: integer }?
  fstat = async.awaitify(vim.uv.fs_fstat),
  ---@type fun(path: string): string?, { type: string, size: integer }?
  stat = async.awaitify(vim.uv.fs_stat),
}

---@type fun(path: string): string?, uv.uv_fs_t?
local fs_scandir = async.awaitify(vim.uv.fs_scandir)

---@param path string
---@return string?
---@return fun(): string?, string?
M.scandir = function(path)
  local err, handle = fs_scandir(path)
  if err ~= nil or handle == nil then
    return err, lib.noop
  end

  return nil, function()
    return vim.uv.fs_scandir_next(handle)
  end
end

---@param path string
---@return fun(): string?
M.file_lines = function(path)
  return lib.scope(function(defer)
    local e1, fd = M.fs.open(path, "r", 438)
    if e1 or not fd then
      return lib.noop
    end

    defer(function()
      M.fs.close(fd)
    end)

    local e2, stat = M.fs.fstat(fd)
    if e2 or not stat then
      return lib.noop
    end

    local _, data = M.fs.read(fd, stat.size, 0)
    return txt.splitlines(data or "")
  end)
end

M.fn = {
  ---@type fun(cmd: string|string[], opts?: table): integer
  jobstart = async.awaitify(
    ---@param cmd string|string[]
    ---@param opts table?
    ---@param on_exit fun(job_id: integer, code: integer, event: string)
    function(cmd, opts, on_exit)
      opts = opts or {}
      opts.on_exit = on_exit
      vim.fn.jobstart(cmd, opts)
    end
  ),
}

M.ui = {
  ---@generic T
  ---@type fun(items: T[], opts: table): T?, integer?
  select = vim.ui and async.awaitify(vim.ui.select),
}

return M
