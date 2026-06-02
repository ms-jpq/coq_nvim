local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local fs = require "coq.producers.fs"
local lib = require "coq.lib"
local txt = require "coq.lib.text"

local MAX_FILE_BYTES = 65536

local M = {}

---@class paths.IterOpts
---@field max_lines integer
---@field ellipsis? string

---@param data string
---@return boolean
local is_binary = function(data)
  return string.find(data, "\0", 1, true) ~= nil
end

---@param data string
---@param max_lines integer
---@return string[]
local file_lines = function(data, max_lines)
  local lines = {}
  for line in txt.splitlines(data) do
    table.insert(lines, (string.gsub(line, "%s+$", "")))
    if #lines >= max_lines + 1 then
      break
    end
  end
  return lines
end

---@param opts paths.IterOpts
---@param entries string[]
local yield_capped = function(opts, entries)
  local total = #entries
  local limit = math.min(total, opts.max_lines)

  for i = 1, limit do
    if i == opts.max_lines and total > opts.max_lines then
      coroutine.yield(opts.ellipsis or "...")
    else
      coroutine.yield(entries[i])
    end
  end
end

---@param opts paths.IterOpts
---@param cwd? string
---@param path string
local dir_preview = function(opts, cwd, path)
  local err, scan = atools.scandir(path)
  if err then
    coroutine.yield("(scandir: " .. err .. ")")
    return
  end

  local entries = {}
  for name, kind in scan do
    local full = vim.fs.joinpath(path, name)
    local rendered = cwd and fs.fmt_path(cwd, full) or name
    table.insert(entries, rendered .. (kind == "directory" and "/" or ""))
  end
  table.sort(entries)

  yield_capped(opts, entries)
end

---@param opts paths.IterOpts
---@param path string
local file_preview = function(opts, path)
  lib.scope(function(defer)
    local e_open, fd = atools.fs.open(path, "r", 438)
    if e_open or fd == nil then
      coroutine.yield("(open: " .. (e_open or "no fd") .. ")")
      return
    end

    defer(function()
      atools.fs.close(fd)
    end)

    local e_stat, fst = atools.fs.fstat(fd)
    if e_stat or fst == nil then
      coroutine.yield("(fstat: " .. (e_stat or "no stat") .. ")")
      return
    end

    if fst.size == 0 then
      coroutine.yield "(empty)"
      return
    end

    local e_read, data = atools.fs.read(fd, math.min(fst.size, MAX_FILE_BYTES), 0)
    if e_read or data == nil then
      coroutine.yield("(read: " .. (e_read or "no data") .. ")")
      return
    end

    if is_binary(data) then
      coroutine.yield "(binary)"
      return
    end

    yield_capped(opts, file_lines(data, opts.max_lines))
  end)
end

---@param opts paths.IterOpts
---@param cwd? string
---@param path string
---@return lib.Iterator<string>
M.lines = function(opts, cwd, path)
  return async.wrap(function()
    local err, st = atools.fs.stat(path)
    if err or st == nil then
      coroutine.yield("(stat: " .. (err or "no stat") .. ")")
      return
    end

    if st.type == "directory" then
      dir_preview(opts, cwd, path)
    else
      file_preview(opts, path)
    end
  end)
end

return M
