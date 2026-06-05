local match = require "coq.lib.index.rank.match"
local parsers_util = require "coq.producers.snippets.parsers.util"
local path = require "coq.lib.path"
local set = require "coq.lib.set"
local txt = require "coq.lib.text"

local STARTS = {
  ALIAS = "alias",
  COMMENT = "#",
  EXTENDS = "extends",
  INCLUDES = "include",
  LABEL = "abbr",
  SNIPPET = "snippet",
}

local IGNORED_STARTS = { "delete", "options", "regexp", "source" }
local LEGAL_STARTS = vim.tbl_values(STARTS)

---@param line string
---@param prefix string
---@return string
local lstrip = function(line, prefix)
  return vim.trim(string.sub(line, #prefix + 1))
end

local CUTOFF = 2 ^ 24

---@param start string
---@return string?
local did_you_mean = function(start)
  local best, best_score = nil, CUTOFF
  for _, legal in pairs(LEGAL_STARTS) do
    local score = match.score(start, legal)
    if score > best_score then
      best, best_score = legal, score
    end
  end
  return best
end

---@param file string
---@param lineno integer
---@param line string
---@param reason string
---@return string
local format_err = function(file, lineno, line, reason)
  return string.format(
    "Cannot load:\n  path:   %s\n  lineno: %d\n  line:   %s\n  reason: %s",
    file,
    lineno,
    line,
    reason
  )
end

---@param header string
---@return string name
---@return string label
local parse_header = function(header)
  local name, label = string.match(header, "^(%S+) (.*)$")
  name, label = name or header, label or ""

  if string.sub(label, 1, 1) == '"' and select(2, string.gsub(label, '"', '"')) == 2 then
    label = string.match(label, '"([^"]*)"') or label
  end
  return name, label
end

local M = {}

---@param src snippets.Source
---@param text string
---@return string? err
---@return snippets.Extends extends
---@return snippets.Sourced sourced
M.parse = function(src, text)
  local filetype = path.stem(src.path)
  local items = {}
  local extending = set.new {}

  local current_name = ""
  local current_label = ""
  local current_aliases = {}
  local current_lines = {}

  local push = function()
    if current_name == "" then
      return
    end

    local seen = set.new {}
    for _, m in pairs(current_aliases) do
      if m ~= "" and not seen[m] then
        seen[m] = true
        table.insert(items, {
          word = m,
          body = vim.trim(table.concat(txt.dedent(current_lines), "\n")),
          filetype = filetype,
          grammar = "lsp",
          label = current_label,
          doc = "",
        })
      end
    end
  end

  local err = nil
  local lines = vim.iter(txt.splitlines(text)):enumerate()
  for lineno, raw in lines do
    local line = txt.rstrip(raw)

    if vim.startswith(line, STARTS.COMMENT) or txt.startswith(IGNORED_STARTS, line) then
    elseif line == "" then
      table.insert(current_lines, line)
      --
    elseif vim.startswith(line, STARTS.EXTENDS) then
      for ft in vim.gsplit(lstrip(line, STARTS.EXTENDS), ",", { plain = true }) do
        local trimmed = vim.trim(ft)
        if trimmed ~= "" then
          extending[trimmed] = true
        end
      end
      --
    elseif vim.startswith(line, STARTS.INCLUDES) then
      local stem = path.stem(lstrip(line, STARTS.INCLUDES))
      if stem ~= "" then
        extending[stem] = true
      end
      --
    elseif vim.startswith(line, STARTS.SNIPPET) then
      push()
      current_name, current_label = parse_header(lstrip(line, STARTS.SNIPPET))
      current_aliases = { current_name }
      current_lines = {}
      --
    elseif vim.startswith(line, STARTS.ALIAS) then
      table.insert(current_aliases, lstrip(line, STARTS.ALIAS))
      --
    elseif vim.startswith(line, STARTS.LABEL) then
      current_label = lstrip(line, STARTS.LABEL)
      --
    elseif string.match(line, "^%s") then
      if current_name == "" then
        err = format_err(src.path, lineno, line, "Expected snippet name")
        break
      end
      table.insert(current_lines, line)
      --
    else
      local start = string.match(line, "^(%S+)") or line
      local hint = did_you_mean(start)
      local addendum = hint and (" :: did you mean -- " .. hint) or ""
      err = format_err(src.path, lineno, line, "Unexpected line start" .. addendum)
      break
    end
  end

  if err == nil then
    push()
  end

  local extends = next(extending) and { [filetype] = extending } or {}
  return err, extends, parsers_util.sourced(src, { filetype }, items)
end

return M
