local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local fs_cache = require "coq.lib.fs_cache"
local itertools = require "coq.lib.itertools"
local path = require "coq.lib.path"

---@alias snippets.Kind "bundle" | "neosnippet"

---@class snippets.Source
---@field kind snippets.Kind
---@field path string
---@field mtime integer
---@field filetype string

local BUNDLE_NAME = "coq+snippets+v2.json"
local USER_DIR = "coq-user-snippets"

---@param file string
---@return string?
local neosnippet_ft = function(file)
  local name = vim.fs.basename(file)
  for _, ext in pairs { ".snippets", ".snippet", ".snips", ".snip" } do
    if vim.endswith(name, ext) then
      return string.lower(string.sub(name, 1, #name - #ext))
    end
  end
  return nil
end

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return lib.Iterator<string>
local user_dirs = function(settings, idle_ctx)
  local candidates = async.wrap(function()
    for _, rtp in pairs(idle_ctx.rtps) do
      local cand = vim.fs.joinpath(rtp, USER_DIR)
      coroutine.yield(cand)
    end

    local user_path = settings.clients.snippets.user_path
    if not user_path or user_path == "" then
      return
    end

    local expanded = path.join(idle_ctx.config_dir, vim.fs.normalize(user_path))
    coroutine.yield(expanded)
  end)

  return vim.iter(candidates):filter(itertools.uniq_by(function(file)
    local err, st = atools.fs.stat(file)
    return st and not err and (st.dev .. ":" .. st.ino) or nil
  end)) --[[@as lib.Iterator<string>]]
end

---@param filetype? string
---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local bundle = function(filetype, dirs)
  return closable.iter(function()
    for _, dir in pairs(dirs) do
      local file = vim.fs.joinpath(dir, BUNDLE_NAME)
      local mtime = fs_cache.mtime_ns(file)
      if mtime then
        coroutine.yield {
          kind = "bundle",
          path = file,
          mtime = mtime,
          filetype = filetype,
        }
      end
    end
  end)
end

---@param filetype? string
---@param skip? string
---@param dirs string[]
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
local neosnippet = function(filetype, skip, dirs)
  return closable.iter(function(defer)
    for _, dir in pairs(dirs) do
      local close, iter = atools.fs.walk(dir)
      defer(close)

      for file in iter do
        local file_ft = neosnippet_ft(file)
        if file_ft and (filetype == nil or file_ft == filetype) and file ~= skip then
          local mtime = fs_cache.mtime_ns(file)

          if mtime then
            coroutine.yield {
              kind = "neosnippet",
              path = file,
              mtime = mtime,
              filetype = file_ft,
            }
          end
        end
      end
    end
  end)
end

local M = {}

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return string
M.write_dir = function(settings, idle_ctx)
  local user_path = settings.clients.snippets.user_path
  if user_path and user_path ~= "" then
    return path.join(idle_ctx.config_dir, vim.fs.normalize(user_path))
  end

  local rtp = unpack(idle_ctx.rtps)
  return vim.fs.joinpath(rtp, USER_DIR)
end

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@param filetype? string
---@param skip? string
---@return fun() close
---@return lib.Iterator<snippets.Source> iter
M.list = function(settings, idle_ctx, filetype, skip)
  return closable.iter(function(defer)
    local ft = filetype and string.lower(filetype) or nil
    local user = vim.iter(user_dirs(settings, idle_ctx)):totable()
    local yieldfrom = function(close, iter)
      defer(close)
      for src in iter do
        coroutine.yield(src)
      end
    end

    yieldfrom(bundle(ft, idle_ctx.rtps))
    yieldfrom(neosnippet(ft, skip, user))
  end)
end

return M
