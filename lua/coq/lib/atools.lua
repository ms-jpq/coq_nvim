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
    local stdin_pipe = opts.stdin ~= nil and vim.uv.new_pipe(false) or nil
    local stdout_pipe = vim.uv.new_pipe(false)
    local stderr_pipe = vim.uv.new_pipe(false)

    if stdout_pipe == nil or stderr_pipe == nil then
      return nil
    end

    defer(function()
      for _, p in pairs { stdin_pipe, stdout_pipe, stderr_pipe } do
        if not p:is_closing() then
          p:close()
        end
      end
    end)

    local exit_f, stdout_f, stderr_f = async.future(), async.future(), async.future()

    local handle
    handle = vim.uv.spawn(argv[1], {
      args = { unpack(argv, 2) },
      stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
    }, function(code, signal)
      exit_f.resolve(code, signal)
    end)

    if handle == nil then
      return nil
    end

    defer(function()
      if not handle:is_closing() then
        handle:close()
      end
    end)

    local _ = n.handle.on_cancel(function()
      if not handle:is_closing() then
        handle:kill "sigterm"
      end
    end)

    local read = function(pipe, f)
      local chunks = {}
      pipe:read_start(function(_, data)
        if data == nil then
          pipe:read_stop()
          f.resolve(table.concat(chunks))
        else
          table.insert(chunks, data)
        end
      end)
    end
    read(stdout_pipe, stdout_f)
    read(stderr_pipe, stderr_f)

    if stdin_pipe ~= nil then
      stdin_pipe:write(opts.stdin)
      stdin_pipe:shutdown()
    end

    local h = runtime.current()
    local code, signal = exit_f.await(h)
    local stdout = stdout_f.await(h)
    local stderr = stderr_f.await(h)

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
