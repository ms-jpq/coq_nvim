local async = require "coq.lib.async"
local lib = require "coq.lib"
local runtime = require "coq.lib.async.runtime"

local M = {}

---@param client vim.lsp.Client
---@param method string
---@param params table
---@param buf integer
---@return any err
---@return any result
M.request = function(client, method, params, buf)
  return lib.scope(function(defer)
    local f = async.future()
    local ok, req_id = client:request(method, params, function(err, result)
      f.resolve(err, result)
    end, buf)

    if not ok or not req_id then
      return nil, nil
    end
    defer(runtime.current().on_cancel(function()
      client:cancel_request(req_id)
    end))

    return f.await()
  end)
end

---@param ctx ctx.base
---@param item completions.Item
M.enrich = function(ctx, item)
  local lsp = item.meta.lsp
  if not (lsp and lsp.client_id and lsp.item) then
    return
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client or not (client.server_capabilities.completionProvider or {}).resolveProvider then
    return
  end

  local err, resolved = M.request(client, "completionItem/resolve", lsp.item, ctx.buf)
  if err or not resolved then
    return
  end

  lsp.item = vim.tbl_extend("force", lsp.item, resolved) --[[@as lsp.CompletionItem]]
  lsp.additional_text_edits = resolved.additionalTextEdits or lsp.additional_text_edits
  lsp.command = resolved.command or lsp.command
end

---@param ctx ctx.base
---@param lsp completions.ItemLspMeta
M.exec_command = function(ctx, lsp)
  if not (lsp.command and lsp.client_id) then
    return
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client then
    return
  end

  client:exec_cmd(lsp.command, { bufnr = ctx.buf })
end

return M
