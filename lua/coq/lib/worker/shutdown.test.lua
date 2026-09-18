local T = require "coq.lib.test"
local async = require "coq.lib.async"

local shutdown = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local async = require "coq.lib.async"
local worker = require "coq.lib.worker"
local marker = vim.fn.tempname()
_G.shutdown_ready = async.future()

async.entry(function()
  local ok, err = pcall(function()
    local new_thread = vim.uv.new_thread
    for _, failure in ipairs { "return", "raise" } do
      local fds
      vim.uv.new_thread = function(_, _, read_fd, write_fd)
        fds = { read_fd, write_fd }
        if failure == "raise" then
          error "thread creation failed"
        end
        return nil, "thread creation failed"
      end
      local spawned, reason = pcall(worker.spawn)
      vim.uv.new_thread = new_thread
      assert(not spawned and tostring(reason):find("thread creation failed", 1, true))
      for _, fd in ipairs(fds) do
        assert(not vim.uv.fs_fstat(fd), "failed startup leaked a descriptor")
      end
    end

    local schedule = vim.schedule
    vim.schedule = function(callback)
      schedule(function()
        vim.api.nvim_exec_autocmds("VimLeavePre", {})
        callback()
      end)
    end
    local spawned, reason = pcall(worker.spawn)
    vim.schedule = schedule
    assert(not spawned and require("coq.lib.async.cancel").is(reason))

    local completed_thread
    vim.uv.new_thread = function(...)
      completed_thread = assert(new_thread(...))
      return completed_thread
    end
    local finished = worker.spawn()
    vim.uv.new_thread = new_thread
    finished.close()
    async.sleep(20)

    for i = 1, 3 do
      _G.shutdown_ready = async.future()
      local active = worker.spawn()
      local n = require("coq.lib.async._nursery").new()
      n.spawn(function()
        pcall(active.queue, function(marker)
          require("coq.lib").scope(function(defer)
            defer(function()
              local fd = assert(vim.uv.fs_open(marker, "w", 384))
              assert(vim.uv.fs_write(fd, "closed", 0))
              assert(vim.uv.fs_close(fd))
            end)
            require("coq.lib.worker").main(function()
              _G.shutdown_ready.resolve()
              require("coq.lib.async").sleep(60000)
            end)
          end)
        end, marker .. i)
      end)
      _G.shutdown_ready.await()
    end

    local reentered = false
    vim.schedule(function() reentered = true end)
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    assert(completed_thread)
    assert(not reentered, "shutdown reentered the editor event loop")
    for i = 1, 3 do
      assert(vim.uv.fs_stat(marker .. i), "shutdown returned before worker cleanup")
      assert(vim.uv.fs_unlink(marker .. i))
    end
  end)
  if not ok then
    io.stderr:write(tostring(err))
    os.exit(1)
  end
  vim.cmd "qa!"
end)()
]]

T.test({ "worker shutdown joins pending callbacks without editor reentry", timeout = 5000 * T.SLOW }, function()
  local result = async.awaitify(vim.system)({
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "-c",
    "lua " .. shutdown,
  }, { timeout = 3000 * T.SLOW })
  T.eq(result, { code = 0, signal = 0, stdout = "", stderr = "" })
end)
