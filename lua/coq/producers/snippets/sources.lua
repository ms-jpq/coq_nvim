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
---@field filetypes string[]

local BUNDLE_NAME = "coq+snippets+v2.json"
local NEOSNIPPET_EXT = ".snip"

---@param settings config.Settings
---@param idle_ctx idle.Ctx
---@return lib.Iterator<string>
local user_dirs = function(settings, idle_ctx)
  local candidates = async.wrap(function()
    for _, rtp in pairs(idle_ctx.rtps) do
      local cand = vim.fs.joinpath(rtp, "coq-user-snippets")
      if atools.fs.readable(cand) then
        coroutine.yield(cand)
      end
    end

    local user_path = settings.clients.snippets.user_path
    if not user_path or user_path == "" then
      return
    end

    local expanded = path.join(idle_ctx.config_dir, vim.fs.normalize(user_path))
    if atools.fs.readable(expanded) then
      coroutine.yield(expanded)
    end
  end)

  return vim.iter(candidates):filter(itertools.uniq_by(function(file)
    local err, st = atools.fs.stat(file)
    return st and not err and (st.dev .. ":" .. st.ino) or nil
  end)) --[[@as lib.Iterator<string>]]
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

        if ok and type(json) == "table" and type(json.snippets) == "table" then
          local ft_set = {}
          for _, snip in pairs(json.snippets) do
            if type(snip) == "table" and type(snip.filetype) == "string" then
              ft_set[snip.filetype] = true
            end
          end

          coroutine.yield {
            kind = "bundle",
            path = file,
            mtime = mtime,
            filetypes = vim.tbl_keys(ft_set),
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
      local close, iter = atools.fs.walk(dir)
      defer(close)

      for file in iter do
        if vim.endswith(file, NEOSNIPPET_EXT) then
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

    local yieldfrom = function(close, iter)
      defer(close)
      for src in iter do
        coroutine.yield(src)
      end
    end

    yieldfrom(bundle(idle_ctx.rtps))
    yieldfrom(neosnippet(user))
  end)
end

return M
