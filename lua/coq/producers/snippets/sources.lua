local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
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
---@return string[]
local user_dirs = function(settings)
  local dirs = {}
  local user_path = settings.clients.snippets.user_path
  if user_path and user_path ~= "" then
    local expanded = vim.fs.normalize(user_path)
    if atools.fs.readable(expanded) then
      table.insert(dirs, expanded)
    end
  end
  for _, rtp in pairs(vim.api.nvim_list_runtime_paths()) do
    local cand = vim.fs.joinpath(rtp, "coq-user-snippets")
    if atools.fs.readable(cand) then
      table.insert(dirs, cand)
    end
  end
  return dirs
end

---@param dir string
---@param exts table<string, true>
---@return lib.Iterator<string>
local walk_files = function(dir, exts)
  return async.wrap(function()
    for path, kind in atools.fs.walk(dir) do
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

---@param path string
---@return string?
local read_file = function(path)
  local close, chunks = atools.fs.scanfile(path)
  local out = vim.iter(chunks):totable()
  close()
  if #out == 0 then
    return nil
  end
  return table.concat(out)
end

local M = {}

---@param _settings config.Settings
---@return lib.Iterator<snippets.Source>
M.bundle = function(_settings)
  return async.wrap(function()
    for _, rtp in pairs(vim.api.nvim_list_runtime_paths()) do
      async.sleep(0)
      local path = vim.fs.joinpath(rtp, BUNDLE_NAME)
      local mtime = fs_cache.mtime_ns(path)
      if mtime then
        local body = read_file(path)
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

---@param settings config.Settings
---@return lib.Iterator<snippets.Source>
M.neosnippet = function(settings)
  return async.wrap(function()
    for _, dir in pairs(user_dirs(settings)) do
      for path in walk_files(dir, NEOSNIPPET_EXTS) do
        async.sleep(0)
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

---@param settings config.Settings
---@return lib.Iterator<snippets.Source>
M.lsp = function(settings)
  return async.wrap(function()
    for _, dir in pairs(user_dirs(settings)) do
      for path in walk_files(dir, LSP_EXTS) do
        async.sleep(0)
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

return M
