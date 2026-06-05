local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

---@class snippets.Bundle
---@field snippets snippets.BundleEntry[]

---@class snippets.BundleEntry
---@field filetype string
---@field content? string
---@field matches? table<string, true>
---@field label? string
---@field doc? string

local M = {}

---@param src snippets.Source
---@return lib.Iterator<snippets.Item>
M.parse = function(src)
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

return M
