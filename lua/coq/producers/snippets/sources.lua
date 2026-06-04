local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local fs_cache = require "coq.lib.fs_cache"

---@alias snippets.Kind "bundle" | "neosnippet" | "lsp"

---@class snippets.Source
---@field kind snippets.Kind
---@field path string
---@field mtime integer
---@field filetypes string[]

local BUNDLE_NAME = "coq+snippets+v2.json"
local NEOSNIPPET_EXTS = { snip = true, snippets = true }
local LSP_EXTS = { json = true }

---@param settings config.Settings
---@param rtps string[]
---@return lib.Iterator<string>
local user_dirs = function(settings, rtps)
  return async.wrap(function()
    local user_path = settings.clients.snippets.user_path

    if user_path and user_path ~= "" then
      local expanded = vim.fs.normalize(user_path)
      if atools.fs.readable(expanded) then
        coroutine.yield(expanded)
      end
    end

    for _, rtp in pairs(rtps) do
      local cand = vim.fs.joinpath(rtp, "coq-user-snippets")
      if atools.fs.readable(cand) then
        coroutine.yield(cand)
      end
    end
  end)
end

---@param dir string
---@param exts table<string, true>
---@return fun() close
---@return lib.Iterator<string> iter
local walk_files = function(dir, exts)
  return closable.iter(function(defer)
    local close, iter = atools.fs.walk(dir)
    defer(close)
    for path, kind in iter do
      if kind == "file" then
        local ext = string.match(path, "%.([^.]+)$")
        if ext and exts[ext] then
          coroutine.yield(path)
        end
      end
    end
  end)
end

---@param path string
---@return string
local stem_of = function(path)
  return (vim.fs.basename(path):gsub("%.[^.]+$", ""))
end

---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local bundle = function(dirs)
  return closable.iter(function()
    for _, dir in pairs(dirs) do
      local path = vim.fs.joinpath(dir, BUNDLE_NAME)
      local mtime = fs_cache.mtime_ns(path)
      if mtime then
        local body = atools.fs.slurp(path)
        local ok, json = pcall(vim.json.decode, body or "")
        if ok and type(json) == "table" and type(json.snippets) == "table" then
          local ft_set = {}
          for _, snip in pairs(json.snippets) do
            if type(snip) == "table" and type(snip.filetype) == "string" then
              ft_set[snip.filetype] = true
            end
          end
          local fts = vim.tbl_keys(ft_set)
          table.sort(fts)
          coroutine.yield {
            kind = "bundle",
            path = path,
            mtime = mtime,
            filetypes = fts,
          }
        end
      end
    end
  end)
end

---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local neosnippet = function(dirs)
  return closable.iter(function(defer)
    for _, dir in pairs(dirs) do
      local close, iter = walk_files(dir, NEOSNIPPET_EXTS)
      defer(close)
      for path in iter do
        local mtime = fs_cache.mtime_ns(path)
        if mtime then
          coroutine.yield {
            kind = "neosnippet",
            path = path,
            mtime = mtime,
            filetypes = { stem_of(path) },
          }
        end
      end
    end
  end)
end

---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local lsp = function(dirs)
  return closable.iter(function(defer)
    for _, dir in pairs(dirs) do
      local close, iter = walk_files(dir, LSP_EXTS)
      defer(close)
      for path in iter do
        local mtime = fs_cache.mtime_ns(path)
        if mtime then
          coroutine.yield {
            kind = "lsp",
            path = path,
            mtime = mtime,
            filetypes = { stem_of(path) },
          }
        end
      end
    end
  end)
end

local M = {}

---@param settings config.Settings
---@param rtps string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
M.list = function(settings, rtps)
  return closable.iter(function(defer)
    local user = vim.iter(user_dirs(settings, rtps)):totable()

    local emit = function(close, iter)
      defer(close)
      for src in iter do
        coroutine.yield(src)
      end
    end

    emit(bundle(rtps))
    emit(neosnippet(user))
    emit(lsp(user))
  end)
end

return M
