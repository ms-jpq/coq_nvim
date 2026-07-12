local T = require "coq.lib.test"
local util = require "coq.producers.lsp.util"

---@type ctx.base
local CTX = { win = 0, buf = 0, pos = { 0, 0 }, line = "", changedtick = 0, filetype = "" }

local LSP = { client_id = 7, item = { label = "fido" } }

---@param client vim.lsp.Client?
---@return boolean ok
local resolve_with_client = function(client)
  local get_client_by_id = vim.lsp.get_client_by_id
  vim.lsp.get_client_by_id = function()
    return client
  end

  local ok = pcall(function()
    T.eq(util.resolve(CTX, LSP), nil)
  end)
  vim.lsp.get_client_by_id = get_client_by_id
  return ok
end

T.describe({ "lsp.util.resolve" }, function(test)
  test({ "missing client is unresolvable" }, function()
    T.eq(resolve_with_client(nil), true)
  end)

  test({ "missing server capabilities are unresolvable" }, function()
    T.eq(resolve_with_client {} --[[@as vim.lsp.Client]], true)
  end)

  test({ "missing completion provider is unresolvable" }, function()
    T.eq(resolve_with_client { server_capabilities = {} } --[[@as vim.lsp.Client]], true)
  end)
end)
