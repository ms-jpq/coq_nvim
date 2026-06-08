local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"

local M = {}

---@param client vim.lsp.Client
---@param method string
---@param params table
---@param buf integer
---@return any err
---@return any result
M.request = function(client, method, params, buf)
  return lib.scope(function(defer)
    atools.scheduled()
    local f = async.future()
    local ok, req_id = client:request(method, params, function(err, result)
      f.resolve(err, result)
    end, buf)

    if not ok then
      return nil, nil
    end

    if req_id then
      defer(async.current().on_cancel(vim.schedule_wrap(function()
        client:cancel_request(req_id)
      end)))
    end

    return f.await()
  end)
end

---@param ctx ctx.base
---@param lsp completions.ItemLspMeta
---@return lsp.CompletionItem? -- raw server result, nil if unresolvable/failed
M.resolve = function(ctx, lsp)
  if not (lsp.client_id and lsp.item) then
    return nil
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client or not (client.server_capabilities.completionProvider or {}).resolveProvider then
    return nil
  end

  local err, resolved = M.request(client, "completionItem/resolve", lsp.item, ctx.buf)
  if err then
    return nil
  end
  return resolved
end

---@param lsp completions.ItemLspMeta
---@param resolved lsp.CompletionItem?
---@return completions.ItemLspMeta -- new table, no mutation; `item` is the source of truth
M.merge = function(lsp, resolved)
  if not resolved then
    return lsp
  end

  return {
    client_id = lsp.client_id,
    position_encoding = lsp.position_encoding,
    item = vim.tbl_extend("force", lsp.item or {}, resolved) --[[@as lsp.CompletionItem]],
  }
end

---@param ctx ctx.base
---@param lsp completions.ItemLspMeta
M.exec_command = function(ctx, lsp)
  local command = lsp.item and lsp.item.command
  if not (command and lsp.client_id) then
    return
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client then
    return
  end

  client:exec_cmd(command, { bufnr = ctx.buf })
end

return M
