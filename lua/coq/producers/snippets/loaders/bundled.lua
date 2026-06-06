local loaders_util = require "coq.producers.snippets.loaders.util"
local set = require "coq.lib.set"

---@class snippets.Bundle
---@field extends string[]
---@field snippets snippets.BundleEntry[]

---@class snippets.BundleEntry
---@field filetype string
---@field grammar "lit"|"lsp"|"snu"
---@field content string
---@field matches lib.Set<string>
---@field label string
---@field doc string

---@param text string
---@return snippets.Bundle?
local decode = function(text)
  local ok, json = pcall(vim.json.decode, text)
  if not ok or type(json) ~= "table" or type(json.snippets) ~= "table" then
    return nil
  end
  return json
end

local M = {}

---@param src snippets.Source
---@param text string
---@return string? err
---@return string[] parents
---@return snippets.Sourced sourced
M.parse = function(src, text)
  local json = decode(text)

  if not json then
    return "snippets: bundle " .. src.path .. " is malformed or missing `snippets`", {}, loaders_util.sourced(src, {})
  end

  local extending = set.new {}
  if type(json.extends) == "table" then
    for _, parent in pairs(json.extends) do
      if type(parent) == "string" and parent ~= "" then
        extending[string.lower(parent)] = true
      end
    end
  end

  local items = vim
    .iter(coroutine.wrap(function()
      for _, snip in pairs(json.snippets) do
        if type(snip) == "table" and type(snip.filetype) == "string" and string.lower(snip.filetype) == src.filetype then
          local matches = type(snip.matches) == "table" and snip.matches or {}
          local content = type(snip.content) == "string" and snip.content or ""
          local label = type(snip.label) == "string" and snip.label or ""
          local doc = type(snip.doc) == "string" and snip.doc or ""
          local grammar = (snip.grammar == "lit" or snip.grammar == "snu") and snip.grammar or "lsp"

          for word in pairs(matches) do
            coroutine.yield {
              word = word,
              body = content,
              filetype = src.filetype,
              grammar = grammar,
              label = label,
              doc = doc,
            }
          end
        end
      end
    end))
    :totable()

  return nil, vim.tbl_keys(extending), loaders_util.sourced(src, items)
end

return M
