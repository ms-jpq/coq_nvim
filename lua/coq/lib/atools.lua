local async = require "coq.lib.async"
local runtime = require "coq.lib.async.runtime"

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
    defer(n.handle.on_cancel(function()
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

    local h = runtime.current()
    local await = function(f)
      return function()
        local ok, value = f.await(h)
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
    proc.stdout = stdout
    proc.stderr = stderr
    return proc
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
