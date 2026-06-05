local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local errs = require "coq.lib.errs"
local fs_cache = require "coq.lib.fs_cache"
local path = require "coq.lib.path"

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
---@param idle_ctx idle.Ctx
---@return lib.Iterator<string>
local user_dirs = function(settings, idle_ctx)
  return async.wrap(function()
    local seen = {}
    local emit = function(file)
      local err, st = atools.fs.stat(file)
      if err or not st then
        return
      end

      local key = st.dev .. ":" .. st.ino
      if not seen[key] then
        seen[key] = true
        coroutine.yield(file)
      end
    end

    local user_path = settings.clients.snippets.user_path
    if user_path and user_path ~= "" then
      local expanded = path.join(idle_ctx.config_dir, vim.fs.normalize(user_path))
      if atools.fs.readable(expanded) then
        emit(expanded)
      end
    end

    for _, rtp in pairs(idle_ctx.rtps) do
      local cand = vim.fs.joinpath(rtp, "coq-user-snippets")
      if atools.fs.readable(cand) then
        emit(cand)
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
    for file in iter do
      local ext = string.match(file, "%.([^.]+)$")
      if ext and exts[ext] then
        coroutine.yield(file)
      end
    end
  end)
end

---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local bundle = function(dirs)
  return closable.iter(function()
    for _, dir in pairs(dirs) do
      local file = vim.fs.joinpath(dir, BUNDLE_NAME)
      local mtime = fs_cache.mtime_ns(file)
      if mtime then
        local body = atools.fs.slurp(file)
        local ok, json = pcall(vim.json.decode, body or "")
        if not ok then
          errs.report("snippets: bundle " .. file .. " is malformed: " .. tostring(json))
        elseif type(json) == "table" and type(json.snippets) == "table" then
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
            path = file,
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
      for file in iter do
        local mtime = fs_cache.mtime_ns(file)
        if mtime then
          coroutine.yield {
            kind = "neosnippet",
            path = file,
            mtime = mtime,
            filetypes = { path.stem(file) },
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
      for file in iter do
        local mtime = fs_cache.mtime_ns(file)
        if mtime then
          coroutine.yield {
            kind = "lsp",
            path = file,
            mtime = mtime,
            filetypes = { path.stem(file) },
          }
        end
      end
    end
  end)
end

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
M.list = function(settings, idle_ctx)
  return closable.iter(function(defer)
    local user = vim.iter(user_dirs(settings, idle_ctx)):totable()

    local emit = function(close, iter)
      defer(close)
      for src in iter do
        coroutine.yield(src)
      end
    end

    emit(bundle(idle_ctx.rtps))
    emit(neosnippet(user))
    emit(lsp(user))
  end)
end

return M
