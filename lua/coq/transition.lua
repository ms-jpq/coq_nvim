local PREFIX = "coq.nvim:"

---@param msg string
local warn = function(msg)
  vim.notify_once(PREFIX .. " " .. msg, vim.log.levels.WARN)
end

local M = {}

M.lsp_ensure_capabilities_noop = function()
  warn "lsp_ensure_capabilities is a no-op in v2 — neovim 0.12's vim.lsp.protocol.make_client_capabilities() already covers what v1 used to inject. Drop the wrapping call."
end

M.deps_noop = function()
  warn "coq.deps / :COQdeps is a no-op in v2 — there is no python runtime to install. Remove the call from your bootstrap."
end

return M
