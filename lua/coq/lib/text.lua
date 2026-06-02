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

return M
