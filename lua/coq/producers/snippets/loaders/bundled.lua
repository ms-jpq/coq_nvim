local loaders_util = require "coq.producers.snippets.loaders.util"
local set = require "coq.lib.set"

---@class snippets.Bundle
---@field exts table<string, lib.Set<string>>
---@field snippets table<string, snippets.BundleEntry>

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
---@return snippets.Extends extends
---@return snippets.Sourced sourced
M.parse = function(src, text)
  local json = decode(text)

  if not json then
    return "snippets: bundle " .. src.path .. " is malformed or missing `snippets`",
      {},
      loaders_util.sourced(src, {}, {})
  end

  local ft_set = set.new {}
  local items = vim
    .iter(coroutine.wrap(function()
      for _, snip in pairs(json.snippets) do
        if type(snip) == "table" and type(snip.filetype) == "string" then
          ft_set[snip.filetype] = true
          local matches = type(snip.matches) == "table" and snip.matches or {}
          local content = type(snip.content) == "string" and snip.content or ""
          local doc = type(snip.doc) == "string" and snip.doc or ""
          local label = type(snip.label) == "string" and snip.label or ""
          local grammar = (snip.grammar == "lit" or snip.grammar == "snu") and snip.grammar or "lsp"

          for word in pairs(matches) do
            coroutine.yield {
              word = word,
              body = content,
              filetype = snip.filetype,
              grammar = grammar,
              label = label,
              doc = doc,
            }
          end
        end
      end
    end))
    :totable()

  local extends = type(json.exts) == "table" and json.exts or {}
  return nil, extends, loaders_util.sourced(src, vim.tbl_keys(ft_set), items)
end

return M
