local async = require "coq.lib.async"
local lib = require "coq.lib"
local segment = require "coq.producers.paths.segment"
local threaded = require "coq.lib.producers.threaded"

local M = {}

local FS_SEPS = lib.is_windows and { ["/"] = true, ["\\"] = true } or { ["/"] = true }

---@param p string
---@return boolean
local is_absolute = function(p)
  if string.sub(p, 1, 1) == "/" then
    return true
  end
  return lib.is_windows and (string.sub(p, 1, 1) == "\\" or string.match(p, "^%a:") ~= nil)
end

---@param p string
---@param base string
---@return string
local resolve_path = function(p, base)
  if p == "" then
    return base
  end
  if is_absolute(p) then
    return p
  end
  return vim.fs.joinpath(base, p)
end

---@param p string
---@return boolean
local is_only_seps = function(p)
  for i = 1, #p do
    if not FS_SEPS[string.sub(p, i, i)] then
      return false
    end
  end
  return true
end

---@param path string
---@return boolean
local is_dir = function(path)
  local st = vim.uv.fs_stat(path)
  return (st and st.type == "directory") or false
end

---@param dir string
---@return fun(): string?, string?
local scandir = function(dir)
  local fd = vim.uv.fs_scandir(dir)
  return function()
    if not fd then
      return nil
    end
    return vim.uv.fs_scandir_next(fd)
  end
end

---@param rhs string
---@param name string
---@return boolean
local name_matches = function(rhs, name)
  if rhs == "" then
    return true
  end
  if string.sub(rhs, 1, #name) == name then
    return false
  end
  return string.sub(string.lower(name), 1, #rhs) == string.lower(rhs)
end

---@param opts config.PathsClient
---@return table<string, true>
local resolve_seps = function(opts)
  local seps = {}
  for _, s in ipairs(opts.path_seps) do
    if FS_SEPS[s] then
      seps[s] = true
    end
  end
  return next(seps) and seps or FS_SEPS
end

---@param resolution string[]
---@param ctx ctx.full
---@return lib.Iterator<string>
local collect_bases = function(resolution, ctx)
  return async.wrap(function()
    for _, r in ipairs(resolution) do
      if r == "cwd" then
        coroutine.yield(ctx.cwd)
      elseif r == "file" and ctx.filename ~= "" then
        coroutine.yield(vim.fs.dirname(ctx.filename))
      end
    end
  end)
end

---@param s0 string
---@return lib.Iterator<string>
local variants_of = function(s0)
  return async.wrap(function()
    coroutine.yield(s0)
    local with_user = segment.expanduser(s0)
    if with_user ~= s0 then
      coroutine.yield(with_user)
    end
    local with_vars = segment.expandvars(with_user)
    if with_vars ~= with_user then
      coroutine.yield(with_vars)
    end
  end)
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.paths
  local sc = settings.display.pum.source_context
  local menu = sc[1] .. opts.short_name .. sc[2]
  local local_sep = segment.p_sep(ctx.line_before)
  local cursor_row = ctx.pos[1] - 1

  local seps = resolve_seps(opts)
  local line = ctx.line_before .. ctx.line_after
  local seen = {}

  ---@param dir string
  ---@param name string
  ---@param rhs string
  ---@param segment_start integer
  local emit = function(dir, name, rhs, segment_start)
    local full = vim.fs.joinpath(dir, name)
    local dir_q = is_dir(full)
    local trailing = dir_q and local_sep or ""
    local word = name .. trailing
    if seen[word] then
      return
    end
    seen[word] = true

    local typed_prefix = string.sub(ctx.line_before, segment_start + 1, #ctx.line_before - #rhs)
    local new_text = typed_prefix .. name .. trailing

    coroutine.yield {
      word = word,
      kind = dir_q and "Folder" or "File",
      menu = menu,
      meta = {
        filter = word,
        source = opts.short_name,
        always_on_top = opts.always_on_top,
        path = full,
        lsp = {
          position_encoding = "utf-8",
          item = {
            textEdit = {
              range = {
                start = { line = cursor_row, character = segment_start },
                ["end"] = { line = cursor_row, character = #ctx.line_before },
              },
              newText = new_text,
            },
          },
        },
      },
    }
  end

  ---@param s0 string
  ---@param base string
  ---@param segment_start integer
  ---@return boolean yielded
  local try_s0 = function(s0, base, segment_start)
    if s0 == "" or is_only_seps(s0) then
      return false
    end

    local entire = resolve_path(s0, base)
    if is_dir(entire) then
      local hit = false
      for name in scandir(entire) do
        emit(entire, name, "", segment_start)
        hit = true
      end
      return hit
    end

    local lft, sep, rhs = segment.rpartition(s0, local_sep)
    if sep == "" then
      return false
    end
    local left = resolve_path(lft .. sep, base)
    if not is_dir(left) then
      return false
    end

    local hit = false
    for name in scandir(left) do
      if name_matches(rhs, name) then
        emit(left, name, rhs, segment_start)
        hit = true
      end
    end
    return hit
  end

  for base in collect_bases(opts.resolution, ctx) do
    for cut in segment.iter_cuts(seps, line) do
      if cut.segment_start >= #ctx.line_before then
        break
      end
      for v in variants_of(cut.s0) do
        if try_s0(v, base, cut.segment_start) then
          goto next_base
        end
      end
    end
    ::next_base::
  end
end

---@param settings config.Settings
---@return producers.Producer<ctx.full>
M.new = function(settings)
  return threaded.new {
    settings = settings,
    max_pulls = settings.clients.paths.max_pulls,
    bind = lib.noop,
    idle = lib.noop,
    matcher = function(...)
      require("coq.producers.paths").matcher(...)
    end,
  }
end

return M
