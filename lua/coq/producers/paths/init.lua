local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local lib = require "coq.lib"
local match = require "coq.lib.index.rank.match"
local parse = require "coq.producers.paths.parse"
local util = require "coq.producers.util"

local M = {}

---@param path string
---@param type string
---@return string
local resolve_type = function(path, type)
  if type ~= "link" then
    return type
  end
  local _, st = atools.fs.stat(path)
  return (st and st.type) or type
end

---@param resolution string[]
---@param ctx ctx.full
---@return lib.Iterator<string>
local collect_bases = function(resolution, ctx)
  return coroutine.wrap(function()
    for _, r in pairs(resolution) do
      if r == "cwd" then
        coroutine.yield(ctx.cwd)
      elseif r == "file" and ctx.filename ~= "" then
        coroutine.yield(vim.fs.dirname(ctx.filename))
      end
    end
  end)
end

---@param bases string[]
---@param cand paths.parse.Candidate
---@return lib.Iterator<string>
local cand_dirs = function(bases, cand)
  return coroutine.wrap(function()
    if cand.absolute then
      coroutine.yield(cand.resolved_directory)
      return
    end
    for _, base in pairs(bases) do
      local abs = vim.fs.joinpath(base, cand.resolved_directory)
      coroutine.yield(abs)
    end
  end)
end

---@class paths.Match
---@field cand paths.parse.Candidate
---@field dir string
---@field name string
---@field type string
---@field full string
---@field fuzzy integer

---@param settings config.Settings
---@param ctx ctx.full
---@return fun() close
---@return lib.Iterator<paths.Match> iter
local matches = function(settings, ctx)
  return closable.iter(function(defer)
    local bases = vim.iter(collect_bases(settings.clients.paths.resolution, ctx)):totable()
    local opts = {
      is_windows = lib.is_windows,
      env = vim.uv.os_environ(),
      home = vim.uv.os_homedir() or "",
      path_seps = settings.clients.paths.path_seps or {},
    }

    for cand in parse.candidates(ctx.line_before, opts) do
      local found = false
      for dir in cand_dirs(bases, cand) do
        if atools.fs.is_dir(dir) then
          found = true
          local close, iter = atools.fs.scandir(dir)
          defer(close)

          for name, type in iter do
            local fuzzy = cand.partial == "" and 0 or match.score(cand.partial, name)
            if cand.partial == "" or fuzzy > 0 then
              local full = vim.fs.joinpath(dir, name)
              coroutine.yield {
                cand = cand,
                dir = dir,
                name = name,
                type = resolve_type(full, type),
                full = full,
                fuzzy = fuzzy,
              }
            end
          end
        end
      end

      if found then
        return
      end
    end
  end)
end

---@param m paths.Match
---@return string
local match_key = function(m)
  return m.cand.start .. "\0" .. m.name
end

---@param settings config.Settings
M.matcher = util.batched(function(settings, ctx)
  local row, col = unpack(ctx.pos)
  local line = row - 1

  lib.scope(function(defer)
    local close, iter = matches(settings, ctx)
    defer(close)

    for m in vim.iter(iter):unique(match_key) do
      local dir_q = m.type == "directory"
      local word = m.name .. (dir_q and m.cand.local_sep or "")
      local filter = m.name

      local item = util.item(settings, settings.clients.paths, {
        word = word,
        kind = dir_q and "Folder" or "File",
        filter = filter,
        fuzzy = m.fuzzy,
        path = m.full,
        lsp = {
          position_encoding = "utf-8",
          item = {
            label = word,
            textEdit = {
              range = {
                start = { line = line, character = m.cand.start },
                ["end"] = { line = line, character = col },
              },
              newText = m.cand.literal_directory .. word,
            },
          },
        },
      })
      coroutine.yield(item)
    end
  end)
end)

M.idle = lib.noop

M.new = util.threaded_module "coq.producers.paths"

return M
