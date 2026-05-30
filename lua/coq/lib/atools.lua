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
    local stdin_pipe = opts.stdin ~= nil and vim.uv.new_pipe() or nil
    local stdout_pipe, stderr_pipe = vim.uv.new_pipe(), vim.uv.new_pipe()
    assert(stdout_pipe)
    assert(stderr_pipe)

    for _, p in pairs { stdout_pipe, stderr_pipe, stdin_pipe } do
      defer(function()
        if not p:is_closing() then
          p:close()
        end
      end)
    end

    local exit_f, stdout_f, stderr_f, stdin_f = async.future(), async.future(), async.future(), async.future()

    local handle = vim.uv.spawn(argv[1], {
      args = { unpack(argv, 2) },
      stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
    }, function(code, signal)
      exit_f.resolve(code, signal)
    end)
    assert(handle)

    defer(function()
      if not handle:is_closing() then
        handle:close()
      end
    end)

    defer(n.handle.on_cancel(function()
      if not handle:is_closing() then
        handle:kill "sigterm"
      end
    end))

    if stdin_pipe ~= nil then
      stdin_pipe:write(opts.stdin, function(write_err)
        if write_err ~= nil then
          stdin_f.resolve(write_err)
        else
          stdin_pipe:shutdown(stdin_f.resolve)
        end
      end)
    else
      stdin_f.resolve()
    end

    local read = function(pipe, f)
      local chunks = {}
      pipe:read_start(function(err, data)
        if err ~= nil then
          pipe:read_stop()
          f.resolve(nil, err)
        elseif data == nil then
          pipe:read_stop()
          f.resolve(table.concat(chunks))
        else
          table.insert(chunks, data)
        end
      end)
    end
    read(stdout_pipe, stdout_f)
    read(stderr_pipe, stderr_f)

    local h = runtime.current()
    local check = function(f)
      return function()
        local value, err = f.await(h)
        if err ~= nil then
          error(err, 0)
        end
        return value
      end
    end

    local _, exit, stdout, stderr = unpack(async.all {
      check(stdin_f),
      function()
        return { exit_f.await(h) }
      end,
      check(stdout_f),
      check(stderr_f),
    })
    local code, signal = unpack(exit)

    return {
      code = code,
      signal = signal,
      stdout = stdout,
      stderr = stderr,
    }
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
  select = async.awaitify(vim.ui.select),
}

return M
