local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local itertools = require "coq.lib.itertools"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local txt = require "coq.lib.text"

local MAX_BYTES = 1024 * 1024

local M = {}

---@class paths.IterOpts
---@field max_lines integer
---@field ellipsis? string

---@param data string
---@return boolean
local is_binary = function(data)
  return string.find(data, "\0", 1, true) ~= nil
end

---@param opts paths.IterOpts
---@param entries lib.Iterator<string>
local yield_capped = function(opts, entries)
  local capped = vim.iter(entries):take(opts.max_lines + 1):enumerate()
  for i, v in capped do
    if i == opts.max_lines and capped:peek() ~= nil then
      coroutine.yield(opts.ellipsis or "...")
      return
    end
    coroutine.yield(v)
  end
end

---@param opts paths.IterOpts
---@param cwd? string
---@param path string
local dir_preview = function(opts, cwd, path)
  local entries = {}
  lib.scope(function(defer)
    local close, iter = atools.fs.scandir(path)
    defer(close)
    for name, kind in iter do
      local full = vim.fs.joinpath(path, name)
      local rendered = cwd and path_fmt.fmt(cwd, full) or name
      table.insert(entries, rendered .. (kind == "directory" and "/" or ""))
    end
  end)
  table.sort(entries)

  yield_capped(opts, vim.iter(entries) --[[@as lib.Iterator<string>]])
end

---@param opts paths.IterOpts
---@param path string
local file_preview = function(opts, path)
  local text = lib.scope(function(defer)
    local close, iter = atools.fs.scanfile(path)
    defer(close)
    local seen = 0
    local capped = itertools.take_while(function(chunk)
      seen = seen + #chunk
      return seen <= MAX_BYTES
    end, iter)
    return table.concat(vim.iter(capped):totable())
  end)

  if text == "" then
    coroutine.yield "(empty)"
    return
  end

  if is_binary(text) then
    coroutine.yield "(binary)"
    return
  end

  yield_capped(
    opts,
    vim.iter(txt.splitlines(text)):map(function(line)
      return (string.gsub(line, "%s+$", ""))
    end) --[[@as lib.Iterator<string>]]
  )
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
