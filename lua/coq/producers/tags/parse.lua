local async = require "coq.lib.async"
local txt = require "coq.lib.text"

---@class tags.Tag
---@field word string
---@field path string
---@field line integer
---@field kind string
---@field language string
---@field scope? string
---@field scopeKind? string
---@field typeref? string
---@field access? string
---@field signature? string
---@field pattern? string

local M = {}

---@param pattern string
---@return string
local unescape = function(pattern)
  local inner = string.sub(pattern, 2, -2)
  inner = string.gsub(inner, "^%^", "")
  inner = string.gsub(inner, "%$$", "")
  inner = vim.trim(inner)

  local out = {}
  local i = 1
  while i <= #inner do
    local c = string.sub(inner, i, i)
    if c == "\\" then
      local nc = string.sub(inner, i + 1, i + 1)
      if nc == "/" or nc == "\\" then
        table.insert(out, nc)
      end
      i = i + 2
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return table.concat(out)
end

---@param jsonl string
---@return lib.Iterator<tags.Tag>
M.parse = function(jsonl)
  return async.wrap(function()
    for line in txt.splitlines(jsonl) do
      if line ~= "" then
        local ok, obj = pcall(vim.json.decode, line)
        if ok and type(obj) == "table" and obj._type == "tag" and obj.name and obj.path then
          coroutine.yield {
            word = obj.name,
            path = obj.path,
            line = obj.line or 0,
            kind = obj.kind or "",
            language = (obj.language or ""):lower(),
            scope = obj.scope,
            scopeKind = obj.scopeKind,
            typeref = obj.typeref,
            access = obj.access,
            signature = obj.signature,
            pattern = obj.pattern and unescape(obj.pattern) or nil,
          }
        end
      end
    end
  end)
end

return M
