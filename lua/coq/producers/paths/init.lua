local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local producer = require "coq.lib.producers"

local M = {}

local FS_SEPS = lib.is_windows and { ["/"] = true, ["\\"] = true } or { ["/"] = true }

---@param lhs string
---@return string
local p_lhs = function(lhs)
  if string.sub(lhs, -2) == ".." then
    return ".."
  end
  if string.sub(lhs, -1) == "." then
    return "."
  end
  if string.sub(lhs, -1) == "~" then
    return "~"
  end

  if lib.is_windows then
    local drive = string.match(lhs, "(%a):$")
    if drive then
      return drive .. ":"
    end
    local winvar = string.match(lhs, "%%([%w_]+)%%$")
    if winvar then
      return "%" .. winvar .. "%"
    end
  end

  local bracevar = string.match(lhs, "%${([%w_]+)}$")
  if bracevar then
    return "${" .. bracevar .. "}"
  end

  local var = string.match(lhs, "%$([%w_]+)$")
  if var and os.getenv(var) then
    return "$" .. var
  end

  return ""
end

---@param seps table<string, true>
---@param line string
---@return string[]
local separate = function(seps, line)
  local out = { line }
  for sep in pairs(seps) do
    local next_out = {}
    for _, seg in ipairs(out) do
      local acc = {}
      for i = 1, #seg do
        local c = string.sub(seg, i, i)
        if c == sep then
          table.insert(next_out, table.concat(acc))
          acc = {}
        end
        table.insert(acc, c)
      end
      if #acc > 0 then
        table.insert(next_out, table.concat(acc))
      end
    end
    out = next_out
  end
  return out
end

---@class paths.Cut
---@field segment string
---@field s0 string
---@field segment_start integer

---@param seps table<string, true>
---@param line string
---@return lib.Iterator<paths.Cut>
local iter_cuts = function(seps, line)
  return async.wrap(function()
    local parts = separate(seps, line)
    local seg_start = 0
    for idx = 2, #parts do
      local segment = parts[idx - 1]
      local rhs_parts = {}
      for j = idx, #parts do
        table.insert(rhs_parts, parts[j])
      end
      coroutine.yield {
        segment = segment,
        s0 = p_lhs(segment) .. table.concat(rhs_parts),
        segment_start = seg_start,
      }
      seg_start = seg_start + #segment
    end
  end)
end

---@param line_pre string
---@return string
local p_sep = function(line_pre)
  if not lib.is_windows then
    return "/"
  end
  local _, last_fwd = string.find(line_pre, ".*/")
  local _, last_back = string.find(line_pre, ".*\\")
  return ((last_back or 0) > (last_fwd or 0)) and "\\" or "/"
end

---@param s string
---@param sep string
---@return string lft
---@return string sep
---@return string rhs
local rpartition = function(s, sep)
  local last = 0
  local i = 1
  while true do
    local pos = string.find(s, sep, i, true)
    if not pos then
      break
    end
    last = pos
    i = pos + 1
  end
  if last == 0 then
    return "", "", s
  end
  return string.sub(s, 1, last - 1), sep, string.sub(s, last + 1)
end

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
  local err, st = atools.fs.stat(path)
  return (not err and st and st.type == "directory") or false
end

---@param dir string
---@return fun(): string?, string?
local scandir = function(dir)
  local err, iter = atools.scandir(dir)
  if err then
    return lib.noop
  end
  return iter
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
    local normalized = vim.fs.normalize(s0)
    if normalized ~= s0 then
      coroutine.yield(normalized)
    end
  end)
end

---@class paths.MatchCtx
---@field opts config.PathsClient
---@field menu string
---@field local_sep string
---@field cursor_row integer
---@field cursor_col integer
---@field line_before string
---@field seen table<string, true>

---@param mc paths.MatchCtx
---@param dir string
---@param name string
---@param rhs string
---@param segment_start integer
local emit = function(mc, dir, name, rhs, segment_start)
  local full = vim.fs.joinpath(dir, name)
  local dir_q = is_dir(full)
  local trailing = dir_q and mc.local_sep or ""
  local word = name .. trailing
  if mc.seen[word] then
    return
  end
  mc.seen[word] = true

  local typed_prefix = string.sub(mc.line_before, segment_start + 1, mc.cursor_col - #rhs)
  coroutine.yield {
    word = word,
    kind = dir_q and "Folder" or "File",
    menu = mc.menu,
    meta = {
      filter = name,
      source = mc.opts.short_name,
      always_on_top = mc.opts.always_on_top,
      path = full,
      lsp = {
        position_encoding = "utf-8",
        item = {
          textEdit = {
            range = {
              start = { line = mc.cursor_row, character = segment_start },
              ["end"] = { line = mc.cursor_row, character = mc.cursor_col },
            },
            newText = typed_prefix .. name .. trailing,
          },
        },
      },
    },
  }
end

---@param mc paths.MatchCtx
---@param s0 string
---@param base string
---@param segment_start integer
---@return boolean yielded
local try_s0 = function(mc, s0, base, segment_start)
  if s0 == "" or is_only_seps(s0) then
    return false
  end

  local dir, rhs
  local entire = resolve_path(s0, base)
  if is_dir(entire) then
    dir, rhs = entire, ""
  else
    local lft, sep, partial = rpartition(s0, mc.local_sep)
    if sep == "" then
      return false
    end
    local left = resolve_path(lft .. sep, base)
    if not is_dir(left) then
      return false
    end
    dir, rhs = left, partial
  end

  local hit = false
  for name in scandir(dir) do
    if name_matches(rhs, name) then
      emit(mc, dir, name, rhs, segment_start)
      hit = true
    end
  end
  return hit
end

---@param settings config.Settings
M.matcher = function(settings, ctx)
  local opts = settings.clients.paths
  local sc = settings.display.pum.source_context
  ---@type paths.MatchCtx
  local mc = {
    opts = opts,
    menu = sc[1] .. opts.short_name .. sc[2],
    local_sep = p_sep(ctx.line_before),
    cursor_row = ctx.pos[1] - 1,
    cursor_col = #ctx.line_before,
    line_before = ctx.line_before,
    seen = {},
  }

  local seps = resolve_seps(opts)
  local line = ctx.line_before .. ctx.line_after

  for base in collect_bases(opts.resolution, ctx) do
    for cut in iter_cuts(seps, line) do
      if cut.segment_start >= mc.cursor_col then
        break
      end
      for v in variants_of(cut.s0) do
        if try_s0(mc, v, base, cut.segment_start) then
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
  return producer.threaded {
    settings = settings,
    bind = lib.noop,
    idle = lib.noop,
    matcher = function(...)
      require("coq.producers.paths").matcher(...)
    end,
  }
end

M._internal = {
  p_lhs = p_lhs,
  separate = separate,
  iter_cuts = iter_cuts,
  p_sep = p_sep,
  rpartition = rpartition,
}

return M
