---@class snippets.Source
---@field path string
---@field mtime integer
---@field filetypes string[] which filetypes this source contributes to

---@class snippets.Loader
---@field sources fun(): snippets.Source[]
---@field load fun(source: snippets.Source): snippets.Item[]

local M = {}

---@type snippets.Loader
M.bundle = {
  sources = function()
    return {}
  end,
  load = function(_)
    return {}
  end,
}

---@type snippets.Loader
M.neosnippet = {
  sources = function()
    return {}
  end,
  load = function(_)
    return {}
  end,
}

---@type snippets.Loader
M.lsp = {
  sources = function()
    return {}
  end,
  load = function(_)
    return {}
  end,
}

---@type snippets.Loader[]
local LOADERS = { M.bundle, M.neosnippet, M.lsp }

---@return table<string, snippets.Source[]>
M.sources_by_filetype = function()
  local out = {}
  for _, loader in pairs(LOADERS) do
    for _, src in pairs(loader.sources()) do
      for _, ft in pairs(src.filetypes) do
        out[ft] = out[ft] or {}
        table.insert(out[ft], src)
      end
    end
  end
  return out
end

---@param filetype string
---@return snippets.Item[]
M.parse = function(filetype)
  local out = {}
  for _, loader in pairs(LOADERS) do
    for _, src in pairs(loader.sources()) do
      if vim.tbl_contains(src.filetypes, filetype) then
        for _, item in pairs(loader.load(src)) do
          if item.filetype == filetype then
            table.insert(out, item)
          end
        end
      end
    end
  end
  return out
end

return M
