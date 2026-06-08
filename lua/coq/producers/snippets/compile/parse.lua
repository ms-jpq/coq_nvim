local json = require "coq.lib.json"
local neosnippet = require "coq.producers.snippets.loaders.neosnippet"
local path_lib = require "coq.lib.path"
local set = require "coq.lib.set"
local txt = require "coq.lib.text"

local M = {}

---@class snippets.LspUnit
---@field prefix? string | string[]
---@field body string | string[]
---@field description? string | string[]

---@alias snippets.LspFile table<string, snippets.LspUnit>

---@param file string
---@param text string
---@return string filetype
---@return string[] extending
---@return snippets.BundleEntry[]
M.lsp = function(file, text)
  local filetype = string.lower(path_lib.stem(file))
  local decoded = json.decode(text)
  if type(decoded) ~= "table" then
    return filetype, {}, {}
  end

  local items = vim
    .iter(decoded)
    :map(function(label, unit)
      if type(unit) ~= "table" then
        return nil
      end

      local content = txt.join_or_str(true, "\n", unit.body)
      local matches = set.new {}
      if unit.prefix == nil then
        matches[content] = true
      else
        for _, w in pairs(txt.as_strings(true, unit.prefix)) do
          matches[w] = true
        end
      end

      return {
        content = content,
        label = type(label) == "string" and label or "",
        doc = txt.join_or_str(true, "\n", unit.description),
        matches = matches,
      }
    end)
    :totable()

  return filetype, {}, items
end

---@param file string
---@param text string
---@return string filetype
---@return string[] extending
---@return snippets.BundleEntry[]
M.neosnippet_like = function(file, text)
  local filetype = string.lower(path_lib.stem(file))
  local src = { filetype = filetype, path = file, mtime = 0 } --[[@as snippets.Source]]
  local err, parents, sourced = neosnippet.parse(src, text)
  if err then
    return filetype, {}, {}
  end

  local items = {}
  for _, it in pairs(sourced.snippets) do
    table.insert(items, {
      content = it.body,
      label = it.label,
      doc = it.doc,
      matches = { [it.word] = true },
    })
  end
  return filetype, parents, items
end

return M
