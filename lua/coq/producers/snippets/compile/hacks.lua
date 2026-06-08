local M = {}

---@param entry snippets.BundleEntry
---@return snippets.BundleEntry
M._js = function(entry)
  entry.content = (string.gsub(entry.content, ";\n", "\n"))
  entry.content = (string.gsub(entry.content, ";$", ""))
  return entry
end

---@type table<string, fun(entry: snippets.BundleEntry): snippets.BundleEntry>
local transforms = {
  javascript = M._js,
  typescript = M._js,
  typescriptreact = M._js,
}

---@param filetype string
---@param entry snippets.BundleEntry
---@return snippets.BundleEntry
M.trans = function(filetype, entry)
  local fn = transforms[filetype]
  return fn and fn(entry) or entry
end

return M
