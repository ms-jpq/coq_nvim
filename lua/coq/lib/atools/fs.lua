local async = require "coq.lib.async"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"

local MODE_RW = tonumber("0644", 8)
local MODE_DIR = tonumber("0755", 8)

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
---@type fun(fd: integer, data: string, offset: integer): uv.error_name?, integer?
local fs_write = async.awaitify(vim.uv.fs_write)
---@type fun(fd: integer): uv.error_name?, uv.fs_stat.result?
local fs_fstat = async.awaitify(vim.uv.fs_fstat)
---@type fun(path: string, mode: integer): uv.error_name?, boolean?
local fs_mkdir = async.awaitify(vim.uv.fs_mkdir)

local M = {}

---@type fun(path: string): uv.error_name?, uv.fs_stat.result?
M.stat = async.awaitify(vim.uv.fs_stat)

---@type fun(old_path: string, new_path: string): uv.error_name?, boolean?
M.rename = async.awaitify(vim.uv.fs_rename)

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
---@param data string
---@return uv.error_name?
M.writefile = function(path, data)
  return lib.scope(function(defer)
    local e1, fd = fs_open(path, "w", MODE_RW)
    if e1 or not fd then
      return e1 or "EINVAL"
    end
    defer(function()
      fs_close(fd)
    end)
    return fs_write(fd, data, -1)
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

return M
