local M = {}

local CR, LF = 13, 10

---@param trim boolean
---@param x any
---@return string[]
M.as_strings = function(trim, x)
  if x == nil then
    return {}
  end

  if type(x) == "string" then
    local t = trim and vim.trim(x) or x
    return trim and t == "" and {} or { t }
  end

  if type(x) == "table" then
    local acc = {}
    for _, v in pairs(x) do
      local t = trim and vim.trim(v) or v
      if not trim or t ~= "" then
        table.insert(acc, t)
      end
    end
    return acc
  end

  error("as_strings: expected string|string[]|nil, got " .. type(x), 2)
end

---@param trim boolean
---@param sep string
---@param x string|string[]|nil
---@return string
M.join_or_str = function(trim, sep, x)
  local joined = table.concat(M.as_strings(false, x), sep)
  return trim and vim.trim(joined) or joined
end

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

---@param haystack string
---@param needle string
---@return integer
M.prefix_overlap = function(haystack, needle)
  local cap = math.min(#haystack, #needle)
  for n = cap, 1, -1 do
    if string.sub(needle, 1, n) == string.sub(haystack, #haystack - n + 1) then
      return n
    end
  end
  return 0
end

---@param haystack string
---@param needle string
---@return integer
M.suffix_overlap = function(haystack, needle)
  local cap = math.min(#haystack, #needle)
  for n = cap, 1, -1 do
    if string.sub(needle, #needle - n + 1) == string.sub(haystack, 1, n) then
      return n
    end
  end
  return 0
end

---@param s string
---@return string
M.lstrip = function(s)
  return (string.gsub(s, "^%s+", ""))
end

---Right-pad `text` with spaces until it is at least `width` columns wide.
---No-op when `#text >= width`.
---@param text string
---@param width integer
---@return string
M.pad_right = function(text, width)
  return width > #text and text .. string.rep(" ", width - #text) or text
end

---@param s string
---@return string
M.rstrip = function(s)
  return (string.gsub(s, "%s+$", ""))
end

---@param prefixes string[]
---@param line string
---@return boolean
M.startswith = function(prefixes, line)
  for _, p in pairs(prefixes) do
    if vim.startswith(line, p) then
      return true
    end
  end
  return false
end

---@param suffixes string[]
---@param line string
---@return boolean
M.endswith = function(suffixes, line)
  for _, s in pairs(suffixes) do
    if vim.endswith(line, s) then
      return true
    end
  end
  return false
end

---@param lines string[]
---@return fun(): string?
M.dedent = function(lines)
  local prefix = nil

  for _, line in ipairs(lines) do
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

  local strip = prefix and prefix ~= "" and prefix or nil
  return coroutine.wrap(function()
    for _, line in ipairs(lines) do
      local l = (strip and vim.startswith(line, strip)) and string.sub(line, #strip + 1) or line
      coroutine.yield(l)
    end
  end)
end

return M
