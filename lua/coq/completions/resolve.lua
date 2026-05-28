local runtime = require "coq.lib.async.runtime"

local M = {}

---@param item completions.Item
---@return completions.ItemLspMeta?
M.resolve = function(item)
  local lsp = item.meta.lsp
  if not (lsp and lsp.client_id and lsp.item) then
    return nil
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client then
    return nil
  end
  if not (client.server_capabilities.completionProvider or {}).resolveProvider then
    return nil
  end

  local f = runtime.future()
  client:request("completionItem/resolve", lsp.item, function(_, result)
    f.resolve(result)
  end, vim.api.nvim_get_current_buf())

  local resolved = f.await(runtime.current())
  if not resolved then
    return nil
  end

  return {
    additional_text_edits = resolved.additionalTextEdits,
    command = resolved.command or lsp.command,
  }
end

---@param lsp completions.ItemLspMeta
M.exec_command = function(lsp)
  if not (lsp.command and lsp.client_id) then
    return
  end

  local client = vim.lsp.get_client_by_id(lsp.client_id)
  if not client then
    return
  end

  client:exec_cmd(lsp.command, { bufnr = vim.api.nvim_get_current_buf() })
end

return M
