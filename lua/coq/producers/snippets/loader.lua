local parsers = require "coq.producers.snippets.parsers"
local sources = require "coq.producers.snippets.sources"

---@class snippets.Loader
---@field sources fun(): table<string, snippets.Source[]>
---@field parse fun(filetype: string): snippets.Item[]

local M = {}

---@param settings config.Settings
---@param rtps string[]
---@return snippets.Loader
M.new = function(settings, rtps)
  ---@diagnostic disable-next-line: missing-fields
  local loader = {} ---@type snippets.Loader

  loader.sources = function()
    local acc = {}
    for src in sources.list(settings, rtps) do
      for _, ft in pairs(src.filetypes) do
        acc[ft] = acc[ft] or {}
        table.insert(acc[ft], src)
      end
    end
    return acc
  end

  loader.parse = function(filetype)
    local out = {}
    for src in sources.list(settings, rtps) do
      if vim.tbl_contains(src.filetypes, filetype) then
        for _, item in pairs(parsers.by_kind[src.kind](src)) do
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
