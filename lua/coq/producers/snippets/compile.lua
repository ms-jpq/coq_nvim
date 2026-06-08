local M = {}

---@param body string
---@return boolean ok
M.validate = function(body)
  local buf = vim.api.nvim_create_buf(false, true)
  local ok = vim.api.nvim_buf_call(buf, function()
    local success = pcall(vim.snippet.expand, body)
    pcall(vim.snippet.stop)
    return success
  end)
  vim.api.nvim_buf_delete(buf, { force = true })
  return ok
end

---@class snippets.BundleV3 : snippets.Bundle

---@param bundle snippets.Bundle
---@return snippets.BundleV3
M.compile = function(bundle)
  local kept = vim
    .iter(bundle.snippets)
    :filter(function(entry)
      return type(entry.content) == "string" and M.validate(entry.content)
    end)
    :totable()

  return {
    extends = bundle.extends or {},
    snippets = kept,
  }
end

return M
