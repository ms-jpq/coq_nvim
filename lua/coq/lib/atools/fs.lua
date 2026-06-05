local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"

local MODE_RW = tonumber("0644", 8)
local MODE_DIR = tonumber("0755", 8)

local R_OWNER = tonumber("400", 8)
local R_GROUP = tonumber("040", 8)
local R_OTHER = tonumber("004", 8)

local UID = vim.uv.getuid and vim.uv.getuid() or -1
local GID = vim.uv.getgid and vim.uv.getgid() or -1

---@type fun(path: string): uv.error_name?, uv.luv_dir_t?
local fs_opendir = async.awaitify(vim.uv.fs_opendir)
---@type fun(dir: uv.luv_dir_t): uv.error_name?, boolean?
local fs_closedir = async.awaitify(vim.uv.fs_closedir, { cancel = false })

---@type fun(path: string, flags: string|integer, mode: integer): uv.error_name?, integer?
local fs_open = async.awaitify(vim.uv.fs_open)
---@type fun(fd: integer): uv.error_name?
local fs_close = async.awaitify(vim.uv.fs_close, { cancel = false })
---@type fun(fd: integer): uv.error_name?, uv.fs_stat.result?
local fs_fstat = async.awaitify(vim.uv.fs_fstat)
---@type fun(path: string, mode: integer): uv.error_name?, boolean?
local fs_mkdir = async.awaitify(vim.uv.fs_mkdir)

---@type fun(path: string): uv.error_name?, uv.fs_stat.result?
local fs_stat = async.awaitify(vim.uv.fs_stat)

---@param fn function
---@return function call
---@return fun() drain
local drainable = function(fn)
  ---@type async.Future?
  local pending = nil

  local invoke = function(...)
    pending = async.future()
    local argv = { ... }
    table.insert(argv, pending.resolve)

    fn(unpack(argv))

    local rets = { pending.await() }
    pending = nil
    return unpack(rets)
  end

  local drain = function()
    if pending then
      pending.await { cancel = false }
    end
  end

  return invoke, drain
end

local M = {}

---@param path string
---@return uv.error_name? err
---@return uv.fs_stat.result? st
---@return boolean readable
M.stat = function(path)
  local err, st = fs_stat(path)
  if err or not st then
    return err, st, false
  end
  local mask = (st.uid == UID and R_OWNER) or (st.gid == GID and R_GROUP) or R_OTHER
  return nil, st, bit.band(st.mode, mask) ~= 0
end

---@param path string
---@return boolean
M.readable = function(path)
  local _, _, readable = M.stat(path)
  return readable
end

---@type fun(old_path: string, new_path: string): uv.error_name?, boolean?
M.rename = async.awaitify(vim.uv.fs_rename)

---@type fun(path: string): uv.error_name?, boolean?
M.unlink = async.awaitify(vim.uv.fs_unlink)

---@param path string
---@return uv.error_name?
M.mkdirp = function(path)
  local err, st = M.stat(path)
  if not err and st and st.type == "directory" then
    return nil
  end

  local p_err = M.mkdirp(vim.fs.dirname(path))
  if p_err then
    return p_err
  end

  local m_err = fs_mkdir(path, MODE_DIR)
  if m_err == "EEXIST" then
    return nil
  end
  return m_err
end

---@param path string
---@return boolean
M.is_dir = function(path)
  local err, st = M.stat(path)
  return (not err and st and st.type == "directory") or false
end

---@param dir string
---@return fun() close
---@return fun(): string?, string? iter
M.walk = function(dir)
  return closable.iter(function(defer)
    local function recurse(d)
      local close, entries = M.scandir(d)
      defer(close)

      for name, kind in entries do
        local path = vim.fs.joinpath(d, name)
        if kind == "directory" then
          recurse(path)
        else
          coroutine.yield(path, kind)
        end
      end
    end
    recurse(dir)
  end)
end

---@param path string
---@return fun() close
---@return fun(): string?, string? iter
M.scandir = function(path)
  return closable.iter(function(defer)
    local err, dir = fs_opendir(path)
    if err ~= nil or dir == nil then
      return
    end

    defer(function()
      fs_closedir(dir)
    end)
    local readdir, drain = drainable(vim.uv.fs_readdir)
    defer(drain)

    while true do
      local e, entries = readdir(dir)
      if e ~= nil or entries == nil then
        return
      end

      for _, entry in pairs(entries) do
        coroutine.yield(entry.name, entry.type)
      end
    end
  end)
end

---@param path string
---@return string?
M.slurp = function(path)
  return lib.scope(function(defer)
    local close, iter = M.scanfile(path)
    defer(close)

    local chunks = vim.iter(iter):totable()
    return #chunks > 0 and table.concat(chunks) or nil
  end)
end

---@param path string
---@param data string
---@return uv.error_name?
M.spit = function(path, data)
  return lib.scope(function(defer)
    local e1, fd = fs_open(path, "w", MODE_RW)
    if e1 or not fd then
      return e1 or "EINVAL"
    end

    defer(function()
      fs_close(fd)
    end)

    local write, drain = drainable(vim.uv.fs_write)
    defer(drain)

    return write(fd, data, -1)
  end)
end

---@param path string
---@return fun() close
---@return lib.Iterator<string> iter
M.scanfile = function(path)
  return closable.iter(function(defer)
    local e1, fd = fs_open(path, "r", 0)
    if e1 ~= nil or fd == nil then
      return
    end

    defer(function()
      fs_close(fd)
    end)

    local read, drain = drainable(vim.uv.fs_read)
    defer(drain)

    local e2, st = fs_fstat(fd)
    if e2 ~= nil or st == nil then
      return
    end

    while true do
      local e, data = read(fd, st.blksize, -1)
      if e ~= nil or data == nil or #data == 0 then
        return
      end
      coroutine.yield(data)
    end
  end)
end

return M
