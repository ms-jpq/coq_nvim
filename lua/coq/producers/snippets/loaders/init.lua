local atools = require "coq.lib.atools"
local bundled = require "coq.producers.snippets.loaders.bundled"
local neosnippet = require "coq.producers.snippets.loaders.neosnippet"

---@class snippets.Sourced: snippets.Source
---@field snippets snippets.Item[]

local M = {}

---@param src snippets.Source
---@return string? err
---@return string[] parents
---@return snippets.Sourced sourced
M.parse = function(src)
  local text = atools.fs.slurp(src.path) or ""
  local loader = vim.endswith(src.path, ".json") and bundled or neosnippet
  return loader.parse(src, text)
end

return M
