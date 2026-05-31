local async = require "coq.lib.async"
local lib = require "coq.lib"

local M = {}

---@param s string
---@param suffix string
---@return boolean
local endswith = function(s, suffix)
  return #s >= #suffix and string.sub(s, -#suffix) == suffix
end

---@param lhs string
---@return string
M.p_lhs = function(lhs)
  if endswith(lhs, "..") then
    return ".."
  end
  if endswith(lhs, ".") then
    return "."
  end
  if endswith(lhs, "~") then
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

---@param sep string
---@param text string
---@return string[]
M.split_keep = function(sep, text)
  local parts = {}
  local acc = {}
  for i = 1, #text do
    local c = string.sub(text, i, i)
    if c == sep then
      table.insert(parts, table.concat(acc))
      acc = {}
    end
    table.insert(acc, c)
  end
  if #acc > 0 then
    table.insert(parts, table.concat(acc))
  end
  return parts
end

---@param seps table<string, true>
---@param line string
---@return string[]
M.separate = function(seps, line)
  local segs = { line }
  for sep in pairs(seps) do
    local next = {}
    for _, seg in ipairs(segs) do
      for _, p in ipairs(M.split_keep(sep, seg)) do
        table.insert(next, p)
      end
    end
    segs = next
  end
  return segs
end

---@class paths.Cut
---@field segment string
---@field s0 string
---@field segment_start integer

---@param seps table<string, true>
---@param line string
---@return lib.Iterator<paths.Cut>
M.iter_cuts = function(seps, line)
  return async.wrap(function()
    local parts = M.separate(seps, line)
    local seg_start = 0

    for idx = 2, #parts do
      local segment = parts[idx - 1]
      local rhs_parts = {}
      for j = idx, #parts do
        table.insert(rhs_parts, parts[j])
      end
      coroutine.yield {
        segment = segment,
        s0 = M.p_lhs(segment) .. table.concat(rhs_parts),
        segment_start = seg_start,
      }
      seg_start = seg_start + #segment
    end
  end)
end

---@param line_pre string
---@return string
M.p_sep = function(line_pre)
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
M.rpartition = function(s, sep)
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
---@return string
M.expanduser = function(p)
  if string.sub(p, 1, 2) == "~/" or p == "~" or string.sub(p, 1, 2) == "~\\" then
    local home = vim.uv.os_homedir() or ""
    return home .. string.sub(p, 2)
  end
  return p
end

---@param p string
---@return string
M.expandvars = function(p)
  local braced = string.gsub(p, "%${([%w_]+)}", function(v)
    return os.getenv(v) or ("${" .. v .. "}")
  end)

  return string.gsub(braced, "%$([%w_]+)", function(v)
    return os.getenv(v) or ("$" .. v)
  end)
end

return M
