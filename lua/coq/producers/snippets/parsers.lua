local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local txt = require "coq.lib.text"

local M = {}

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.bundle = function(src)
  return async.wrap(function()
    local body = atools.fs.slurp(src.path)
    if body == nil then
      return
    end
    local ok, json = pcall(vim.json.decode, body)
    if not ok or type(json) ~= "table" or type(json.snippets) ~= "table" then
      return
    end

    for _, snip in pairs(json.snippets) do
      if type(snip) == "table" and type(snip.filetype) == "string" then
        local matches = type(snip.matches) == "table" and snip.matches or {}
        local doc = type(snip.doc) == "string" and snip.doc ~= "" and snip.doc or nil
        local label = type(snip.label) == "string" and snip.label ~= "" and snip.label or nil
        for word in pairs(matches) do
          coroutine.yield {
            word = word,
            body = snip.content or "",
            filetype = snip.filetype,
            label = label,
            doc = doc,
          }
        end
      end
    end
  end)
end

local SNIPPET_START = "snippet"
local ALIAS_START = "alias"
local LABEL_START = "abbr"
local EXTENDS_START = "extends"
local INCLUDES_START = "include"
local COMMENT_START = "#"
local IGNORED_STARTS = { "delete", "options", "regexp", "source" }
local LEGAL_STARTS = { SNIPPET_START, ALIAS_START, LABEL_START, EXTENDS_START }

---@param line string
---@return string name
---@return string label
local parse_snippet_header = function(line)
  local rest = vim.trim(string.sub(line, #SNIPPET_START + 1))
  local sp = string.find(rest, " ", 1, true)

  local name, label = "", ""
  if sp == nil then
    name, label = rest, ""
  else
    name = string.sub(rest, 1, sp - 1)
    label = string.sub(rest, sp + 1)
  end
  if string.sub(label, 1, 1) == '"' then
    local after = string.sub(label, 2)
    local _, count = string.gsub(after, '"', '"')
    if count == 1 then
      local close = string.find(after, '"', 1, true)
      label = string.sub(after, 1, close - 1)
    end
  end
  return name, label
end

---@param start string
---@return string?
local suggest = function(start)
  local best, best_score = nil, 0
  for _, legal in pairs(LEGAL_STARTS) do
    local score = 0
    for i = 1, math.min(#start, #legal) do
      if string.lower(string.sub(start, i, i)) == string.lower(string.sub(legal, i, i)) then
        score = score + 1
      else
        break
      end
    end
    if score > best_score then
      best, best_score = legal, score
    end
  end
  return best_score >= 2 and best or nil
end

---@param path string
---@param lineno integer
---@param line string
---@param reason string
local raise_err = function(path, lineno, line, reason)
  error(
    string.format("Cannot load:\n  path:   %s\n  lineno: %d\n  line:   %s\n  reason: %s", path, lineno, line, reason),
    0
  )
end

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.neosnippet = function(src)
  return async.wrap(function()
    local body = atools.fs.slurp(src.path)
    if body == nil then
      return
    end
    local filetype = src.filetypes[1] or ""

    local items = {}
    local current_name = ""
    local current_label = ""
    local current_aliases = {}
    local current_lines = {}

    local push = function()
      if current_name == "" then
        return
      end
      local content = vim.trim(txt.dedent(table.concat(current_lines, "\n")))
      local seen = {}
      for _, m in pairs(current_aliases) do
        if m ~= "" and not seen[m] then
          seen[m] = true
          table.insert(items, {
            word = m,
            body = content,
            filetype = filetype,
            label = current_label ~= "" and current_label or nil,
          })
        end
      end
    end

    local lineno = 0
    for raw in txt.splitlines(body) do
      lineno = lineno + 1
      local line = txt.rstrip(raw)

      if vim.startswith(line, COMMENT_START) or txt.has_any_prefix(IGNORED_STARTS, line) then
        -- skip
      elseif line == "" then
        table.insert(current_lines, "")
      elseif vim.startswith(line, EXTENDS_START) or vim.startswith(line, INCLUDES_START) then
        -- classified (matches v1); filetype inheritance not yet modelled in v2
      elseif vim.startswith(line, SNIPPET_START) then
        push()
        current_name, current_label = parse_snippet_header(line)
        current_aliases = { current_name }
        current_lines = {}
      elseif vim.startswith(line, ALIAS_START) then
        table.insert(current_aliases, vim.trim(string.sub(line, #ALIAS_START + 1)))
      elseif vim.startswith(line, LABEL_START) then
        current_label = vim.trim(string.sub(line, #LABEL_START + 1))
      elseif string.match(line, "^%s") then
        if current_name ~= "" then
          table.insert(current_lines, line)
        else
          raise_err(src.path, lineno, line, "Expected snippet name")
        end
      else
        local start = string.match(line, "^(%S+)") or line
        local hint = suggest(start)
        local addendum = hint and (" :: did you mean -- " .. hint) or ""
        raise_err(src.path, lineno, line, "Unexpected line start" .. addendum)
      end
    end
    push()

    for _, item in pairs(items) do
      coroutine.yield(item)
    end
  end)
end

---@type table<snippets.Kind, fun(src: snippets.Source): lib.Iterator<snippets.Item>>
M.by_kind = {
  bundle = M.bundle,
  neosnippet = M.neosnippet,
}

return M
