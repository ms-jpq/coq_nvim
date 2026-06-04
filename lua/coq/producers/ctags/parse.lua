local async = require "coq.lib.async"
local fs_cache = require "coq.lib.fs_cache"
local txt = require "coq.lib.text"

---@class ctags.Tag
---@field word string
---@field filename string
---@field line integer
---@field kind string
---@field filetype string
---@field scope? string
---@field scopeKind? string
---@field typeref? string
---@field access? string
---@field signature? string
---@field pattern? string

local M = {}

---@param pattern string
---@return string
M._unescape = function(pattern)
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
---@return lib.Iterator<ctags.Tag>
M.parse = function(jsonl)
  return async.wrap(function()
    for line in txt.splitlines(jsonl) do
      if line ~= "" then
        async.sleep(0)
        local obj = fs_cache.decode(line)

        if type(obj) == "table" and obj._type == "tag" and obj.name and obj.path then
          coroutine.yield {
            word = obj.name,
            filename = obj.path,
            line = obj.line or 0,
            kind = obj.kind or "",
            filetype = string.lower(obj.language or ""),
            scope = obj.scope,
            scopeKind = obj.scopeKind,
            typeref = obj.typeref,
            access = obj.access,
            signature = obj.signature,
            pattern = obj.pattern and M._unescape(obj.pattern) or nil,
          }
        end
      end
    end
  end)
end

return M
