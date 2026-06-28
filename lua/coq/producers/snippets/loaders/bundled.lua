local json = require "coq.lib.json"
local loaders_util = require "coq.producers.snippets.loaders.util"
local set = require "coq.lib.set"

---@class snippets.Bundle
---@field extends string[]
---@field snippets snippets.BundleEntry[]

---@class snippets.BundleEntry
---@field content string
---@field matches lib.Set<string>
---@field label string
---@field doc string

local M = {}

---@param src snippets.Source
---@param text string
---@return string? err
---@return string[] parents
---@return snippets.Sourced sourced
M.parse = function(src, text)
  local bundle = json.decode(text) --[[@as snippets.Bundle?]]

  if type(bundle) ~= "table" or type(bundle.snippets) ~= "table" then
    return "snippets: bundle " .. src.path .. " is malformed or missing `snippets`", {}, loaders_util.sourced(src, {})
  end

  local extending = set.new {}
  if type(bundle.extends) == "table" then
    for _, parent in pairs(bundle.extends) do
      if type(parent) == "string" and parent ~= "" then
        extending[string.lower(parent)] = true
      end
    end
  end

  local items = vim
    .iter(coroutine.wrap(function()
      for _, snip in pairs(bundle.snippets) do
        if type(snip) == "table" then
          local matches = type(snip.matches) == "table" and snip.matches or {}
          local content = type(snip.content) == "string" and snip.content or ""
          local label = type(snip.label) == "string" and snip.label or ""
          local doc = type(snip.doc) == "string" and snip.doc or ""

          for word in pairs(matches) do
            coroutine.yield {
              word = word,
              body = content,
              filetype = src.filetype,
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
