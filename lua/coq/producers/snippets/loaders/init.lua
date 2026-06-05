local atools = require "coq.lib.atools"
local bundled = require "coq.producers.snippets.loaders.bundled"
local neosnippet = require "coq.producers.snippets.loaders.neosnippet"

---@class snippets.Sourced: snippets.Source
---@field snippets snippets.Item[]

local by_kind = {
  bundle = bundled,
  neosnippet = neosnippet,
}

local M = {}

---@param src snippets.Source
---@return string? err
---@return string[] parents
---@return snippets.Sourced sourced
M.parse = function(src)
  local text = atools.fs.slurp(src.path) or ""
  return by_kind[src.kind].parse(src, text)
end

return M
