---@class snippets.Source
---@field loader snippets.SubLoader the sub-loader that produced this source
---@field path string
---@field mtime integer
---@field filetypes string[] which filetypes this source contributes to

---@class snippets.SubLoader
---@field sources fun(): snippets.Source[]
---@field load fun(source: snippets.Source): snippets.Item[]

---@class snippets.Loader: snippets.SubLoader
---@field sources_by_filetype fun(): table<string, snippets.Source[]>
---@field parse fun(filetype: string): snippets.Item[]

---Pre-compiled snippet bundles, e.g. `coq+snippets+v2.json` in runtime paths.
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

---Neosnippet `.snip` files under `<rtp>/coq-user-snippets/` or `user_path`.
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

---LSP-format `.code-snippets` / `.json` files under VS Code-style dirs.
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

  ---@diagnostic disable-next-line: missing-fields
  local loader = {} ---@type snippets.Loader

  loader.sources = function()
    local out = {}
    for _, sub in pairs(subs) do
      for _, src in pairs(sub.sources()) do
        src.loader = sub
        table.insert(out, src)
      end
    end
    return out
  end

  loader.load = function(src)
    return src.loader.load(src)
  end

  loader.sources_by_filetype = function()
    local out = {}
    for _, src in pairs(loader.sources()) do
      for _, ft in pairs(src.filetypes) do
        out[ft] = out[ft] or {}
        table.insert(out[ft], src)
      end
    end
    return out
  end

  loader.parse = function(filetype)
    local out = {}
    for _, src in pairs(loader.sources_by_filetype()[filetype] or {}) do
      for _, item in pairs(loader.load(src)) do
        if item.filetype == filetype then
          table.insert(out, item)
        end
      end
    end
    return out
  end

  return loader
end

return M
