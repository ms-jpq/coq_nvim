local M = {}

local CR, LF = 13, 10

---@param s string
---@return lib.Iterator<string>
M.splitlines = function(s)
  local len = #s
  local pos = 1
  local done = false

  return function()
    if done then
      return nil
    end
    if pos > len then
      done = true
      return ""
    end

    local i = pos
    while i <= len do
      local b = string.byte(s, i)
      if b == LF then
        local line = string.sub(s, pos, i - 1)
        pos = i + 1
        return line
      elseif b == CR then
        local line = string.sub(s, pos, i - 1)
        pos = (i < len and string.byte(s, i + 1) == LF) and (i + 2) or (i + 1)
        return line
      end
      i = i + 1
    end

    done = true
    return string.sub(s, pos)
  end
end

---@param s string
---@return boolean
M.is_multiline = function(s)
  return string.find(s, "[\r\n]") ~= nil
end

---@param s string
---@return string
M.lstrip = function(s)
  return (string.gsub(s, "^%s+", ""))
end

---@param s string
---@return string
M.rstrip = function(s)
  return (string.gsub(s, "%s+$", ""))
end

---@param path string
---@return string
M.stem = function(path)
  return (string.gsub(vim.fs.basename(path), "%.[^.]+$", ""))
end

---@param prefixes string[]
---@param line string
---@return boolean
M.has_any_prefix = function(prefixes, line)
  for _, p in pairs(prefixes) do
    if vim.startswith(line, p) then
      return true
    end
  end
  return false
end

---@param body string
---@return string
M.dedent = function(body)
  local lines = vim.split(body, "\n", { plain = true })

  local prefix = nil
  for _, line in pairs(lines) do
    if string.match(line, "%S") then
      local leading = string.match(line, "^[ \t]*")
      if prefix == nil then
        prefix = leading
      else
        local n = 0
        while n < #prefix and n < #leading and string.sub(prefix, n + 1, n + 1) == string.sub(leading, n + 1, n + 1) do
          n = n + 1
        end
        prefix = string.sub(prefix, 1, n)
      end
      if prefix == "" then
        break
      end
    end
  end

  if prefix == nil or prefix == "" then
    return body
  end

  for i, line in ipairs(lines) do
    if vim.startswith(line, prefix) then
      lines[i] = string.sub(line, #prefix + 1)
    end
  end
  return table.concat(lines, "\n")
end

return M
