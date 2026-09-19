local T = require "coq.lib.test"
local async = require "coq.lib.async"

local shutdown = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local async = require "coq.lib.async"
local worker = require "coq.lib.worker"
local marker = vim.fn.tempname()
debug.getregistry = function() error "registry access is forbidden" end
local joined = {}
local create_thread = vim.uv.new_thread
local native_join
vim.uv.new_thread = function(...)
  local thread = assert(create_thread(...))
  local methods = getmetatable(thread).__index
  if not native_join then
    native_join = methods.join
    methods.join = function(self)
      assert(not joined[self], "thread joined twice")
      assert(native_join(self))
      joined[self] = true
      return true
    end
  end
  return thread
end
_G.shutdown_ready = async.future()

async.entry(function()
  local ok, err = pcall(function()
    local new_thread = vim.uv.new_thread
    for _, failure in ipairs { "return", "raise" } do
      local fds, notification
      vim.uv.new_thread = function(_, _, read_fd, write_fd, release_fd, finished)
        fds = { read_fd, write_fd, release_fd }
        notification = finished
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
      assert(notification:is_closing(), "failed startup leaked its notification")
    end

    local pipe, new_async = vim.uv.pipe, vim.uv.new_async
    for _, failure in ipairs { "pipe", "notification" } do
      local fds = {}
      vim.uv.pipe = function(...)
        if failure == "pipe" and #fds == 4 then
          return nil, "release pipe failed"
        end
        local pair = assert(pipe(...))
        table.insert(fds, pair.read)
        table.insert(fds, pair.write)
        return pair
      end
      vim.uv.new_async = function(...)
        if failure == "notification" then
          error "notification failed"
        end
        return new_async(...)
      end
      local spawned, reason = pcall(worker.spawn)
      vim.uv.pipe, vim.uv.new_async = pipe, new_async
      assert(not spawned and tostring(reason):find("failed", 1, true))
      async.sleep(0)
      for _, fd in ipairs(fds) do
        assert(not vim.uv.fs_fstat(fd), "partial startup leaked a descriptor")
      end
      assert(#vim.api.nvim_get_autocmds({event = "VimLeavePre"}) == 0)
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
    assert(joined[completed_thread], "normal close did not join the thread")
    assert(#vim.api.nvim_get_autocmds({event = "VimLeavePre"}) == 0, "normal close retained its exit callback")

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
    assert(vim.tbl_count(joined) == 4, "shutdown did not join every thread")
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

local early_exit = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local async = require "coq.lib.async"
local transport = require "coq.lib.worker.frame_transport"
debug.getregistry = function() error "registry access is forbidden" end
local native_create = vim.uv.new_thread
local joins = 0
vim.uv.new_thread = function(...)
  local thread = assert(native_create(...))
  local methods = getmetatable(thread).__index
  local native_join = methods.join
  methods.join = function(self)
    joins = joins + 1
    assert(joins == 1, "thread joined twice")
    return native_join(self)
  end
  return thread
end

async.entry(function()
  local ok, err = pcall(function()
    local fn = fails and function(read_fd, write_fd)
      vim.uv.fs_close(read_fd)
      vim.uv.fs_close(write_fd)
      error "expected worker failure"
    end or function(read_fd, write_fd)
      vim.uv.fs_close(read_fd)
      vim.uv.fs_close(write_fd)
    end
    local duplex = transport.spawn_worker(fn)
    duplex.reader:close()
    duplex.writer:close()
    while joins == 0 do async.sleep(1) end
    async.sleep(20)
    assert(#vim.api.nvim_get_autocmds({event = "VimLeavePre"}) == 0)
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    assert(joins == 1)
  end)
  if not ok then
    io.stderr:write(tostring(err))
    os.exit(1)
  end
  vim.cmd "qa!"
end)()
]]

for _, case in ipairs {
  { name = "return", fails = false },
  { name = "error", fails = true },
} do
  T.test({ "worker joins after early " .. case.name, timeout = 5000 * T.SLOW }, function()
    local result = async.awaitify(vim.system)({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-c",
      "lua local fails = " .. tostring(case.fails) .. "; " .. early_exit,
    }, { timeout = 3000 * T.SLOW })
    T.eq({ result.code, result.signal, result.stdout }, { 0, 0, "" })
    if case.fails then
      assert(result.stderr:find("expected worker failure", 1, true), result.stderr)
    else
      T.eq(result.stderr, "")
    end
  end)
end

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
