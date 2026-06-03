local async = require "coq.lib.async"
local itertools = require "coq.lib.itertools"

---@alias snippets.Kind "bundle" | "neosnippet" | "lsp"

---@class snippets.Source
---@field kind snippets.Kind
---@field path string
---@field mtime integer
---@field filetypes string[]

---@class snippets.Loader
---@field sources fun(): lib.Iterator<snippets.Source>
---@field sources_by_filetype fun(): table<string, snippets.Source[]>
---@field parse fun(filetype: string): snippets.Item[]

---@param _settings config.Settings
---@return lib.Iterator<snippets.Source>
local bundle_sources = function(_settings)
  return async.wrap(function() end)
end

---@param _settings config.Settings
---@return lib.Iterator<snippets.Source>
local neosnippet_sources = function(_settings)
  return async.wrap(function() end)
end

---@param _settings config.Settings
---@return lib.Iterator<snippets.Source>
local lsp_sources = function(_settings)
  return async.wrap(function() end)
end

---@param _src snippets.Source
---@return snippets.Item[]
local bundle_parse = function(_src)
  return {}
end

---@param _src snippets.Source
---@return snippets.Item[]
local neosnippet_parse = function(_src)
  return {}
end

---@param _src snippets.Source
---@return snippets.Item[]
local lsp_parse = function(_src)
  return {}
end

---@type table<snippets.Kind, fun(src: snippets.Source): snippets.Item[]>
local PARSERS = {
  bundle = bundle_parse,
  neosnippet = neosnippet_parse,
  lsp = lsp_parse,
}

local M = {}

---@param settings config.Settings
---@return snippets.Loader
M.new = function(settings)
  ---@diagnostic disable-next-line: missing-fields
  local loader = {} ---@type snippets.Loader

  loader.sources = function()
    return itertools.chain(bundle_sources(settings), neosnippet_sources(settings), lsp_sources(settings))
  end

  loader.sources_by_filetype = function()
    local acc = {}
    for src in loader.sources() do
      for _, ft in pairs(src.filetypes) do
        acc[ft] = acc[ft] or {}
        table.insert(acc[ft], src)
      end
    end
    return acc
  end

  loader.parse = function(filetype)
    local out = {}
    for src in loader.sources() do
      if vim.tbl_contains(src.filetypes, filetype) then
        for _, item in pairs(PARSERS[src.kind](src)) do
          if item.filetype == filetype then
            table.insert(out, item)
          end
        end
      end
    end
    return out
  end

  return loader
end

return M
