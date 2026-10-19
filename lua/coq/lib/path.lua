local lib = require "coq.lib"
local set = require "coq.lib.set"

local M = {}

---@alias path.Anchor "absolute" | "relative"
M.ANCHOR = {
  absolute = "absolute",
  relative = "relative",
}

---@alias path.Resolution "cwd" | "file"
M.RESOLUTION = {
  cwd = "cwd",
  file = "file",
}

M.HOME = vim.uv.os_homedir() or ""

---@param is_windows boolean
---@return lib.Set<string>
---@return string default
M.seps = function(is_windows)
  local default = is_windows and "\\" or "/"
  return set.new(is_windows and { default, "/" } or { default }), default
end

local DRIVE_PAT = "^%a:[/\\]"

---@param is_windows boolean
---@param p string
---@return boolean
M.is_absolute = function(is_windows, p)
  if is_windows then
    return vim.startswith(p, "/") or vim.startswith(p, "\\") or string.match(p, DRIVE_PAT) ~= nil
  end
  return vim.startswith(p, "/")
end

---@param base string
---@param p string
---@return string
M.join = function(base, p)
  if M.is_absolute(lib.is_windows, p) or base == "" then
    return p
  end
  return vim.fs.joinpath(base, p)
end

---@param p string
---@return string
M.stem = function(p)
  return (string.gsub(vim.fs.basename(p), "(.)%.[^.]+$", "%1"))
end

---@param seps lib.Set<string>
---@param p string
---@return string dir
---@return string rhs
M.split_at_last_sep = function(seps, p)
  for i = #p, 1, -1 do
    if seps[string.sub(p, i, i)] then
      return string.sub(p, 1, i), string.sub(p, i + 1)
    end
  end
  return "", p
end

---@param is_windows boolean
---@param token string
---@return string
M.local_sep = function(is_windows, token)
  local separators, fallback = M.seps(is_windows)
  local directory = M.split_at_last_sep(separators, token)
  return directory ~= "" and string.sub(directory, -1) or fallback
end

---@param resolution path.Resolution[]
---@param ctx ctx.full
---@return lib.Iterator<string>
M.bases = function(resolution, ctx)
  return coroutine.wrap(function()
    for _, base in ipairs(resolution) do
      if base == M.RESOLUTION.cwd then
        coroutine.yield(ctx.cwd)
      elseif base == M.RESOLUTION.file and ctx.filename ~= "" then
        coroutine.yield(vim.fs.dirname(ctx.filename))
      end
    end
  end)
end

return M
