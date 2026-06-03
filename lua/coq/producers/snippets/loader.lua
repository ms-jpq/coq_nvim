local async = require "coq.lib.async"

---@class snippets.Source
---@field path string
---@field mtime integer
---@field filetypes string[]

---@class snippets.SubLoader
---@field sources fun(): snippets.Source[]
---@field load fun(source: snippets.Source): snippets.Item[]

---@class snippets.Loader
---@field sources fun(): lib.Iterator<snippets.Source>
---@field sources_by_filetype fun(): table<string, snippets.Source[]>
---@field parse fun(filetype: string): snippets.Item[]

---@param _settings config.Settings
---@return snippets.SubLoader
local bundle = function(_settings)
  return {
    sources = function()
      return {}
    end,
    load = function(_)
      return {}
    end,
  }
end

---@param _settings config.Settings
---@return snippets.SubLoader
local neosnippet = function(_settings)
  return {
    sources = function()
      return {}
    end,
    load = function(_)
      return {}
    end,
  }
end

---@param _settings config.Settings
---@return snippets.SubLoader
local lsp = function(_settings)
  return {
    sources = function()
      return {}
    end,
    load = function(_)
      return {}
    end,
  }
end

local M = {}

---@param settings config.Settings
---@return snippets.Loader
M.new = function(settings)
  local subs = { bundle(settings), neosnippet(settings), lsp(settings) }

  ---@return lib.Iterator<snippets.SubLoader, snippets.Source>
  local enumerate = function()
    return async.wrap(function()
      for _, sub in pairs(subs) do
        for _, src in pairs(sub.sources()) do
          coroutine.yield(sub, src)
        end
      end
    end)
  end

  ---@diagnostic disable-next-line: missing-fields
  local loader = {} ---@type snippets.Loader

  loader.sources = function()
    return async.wrap(function()
      for _, src in enumerate() do
        coroutine.yield(src)
      end
    end)
  end

  loader.sources_by_filetype = function()
    local out = {}
    for _, src in enumerate() do
      for _, ft in pairs(src.filetypes) do
        out[ft] = out[ft] or {}
        table.insert(out[ft], src)
      end
    end
    return out
  end

  loader.parse = function(filetype)
    local out = {}
    for sub, src in enumerate() do
      if vim.tbl_contains(src.filetypes, filetype) then
        for _, item in pairs(sub.load(src)) do
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
