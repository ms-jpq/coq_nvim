local lib = require "coq.lib"
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
    lib.scope(function(defer)
      local close, iter = sources.list(settings, rtps)
      defer(close)
      for src in iter do
        for _, ft in pairs(src.filetypes) do
          acc[ft] = acc[ft] or {}
          table.insert(acc[ft], src)
        end
      end
    end)
    return acc
  end

  loader.parse = function(filetype)
    local out = {}
    lib.scope(function(defer)
      local close, iter = sources.list(settings, rtps)
      defer(close)
      for src in iter do
        if vim.tbl_contains(src.filetypes, filetype) then
          for item in parsers.by_kind[src.kind](src) do
            if item.filetype == filetype then
              table.insert(out, item)
            end
          end
        end
      end
    end)
    return out
  end

  return loader
end

return M
