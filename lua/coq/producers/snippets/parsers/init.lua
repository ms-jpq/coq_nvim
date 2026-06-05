local bundled = require "coq.producers.snippets.parsers.bundled"
local neosnippet = require "coq.producers.snippets.parsers.neosnippet"

---@class snippets.Sourced: snippets.Source
---@field filetypes string[]
---@field snippets snippets.Item[]

---@class snippets.Parser
---@field parse fun(src: snippets.Source): snippets.Extends, snippets.Sourced

local by_kind = {
  bundle = bundled,
  neosnippet = neosnippet,
}

---@diagnostic disable-next-line: missing-fields
local M = {} ---@type snippets.Parser

---@param src snippets.Source
---@return snippets.Extends extends
---@return snippets.Sourced sourced
M.parse = function(src)
  return by_kind[src.kind].parse(src)
end

return M
