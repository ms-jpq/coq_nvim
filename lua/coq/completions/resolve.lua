local runtime = require "coq.lib.async.runtime"

local M = {}

---@param item completions.Item
---@return completions.ItemMeta?
M.resolve = function(item)
  local meta = item.meta
  if not (meta.client_id and meta.lsp_item) then
    return nil
  end

  local client = vim.lsp.get_client_by_id(meta.client_id)
  if not client then
    return nil
  end
  if not (client.server_capabilities.completionProvider or {}).resolveProvider then
    return nil
  end

  local f = runtime.future()
  client:request("completionItem/resolve", meta.lsp_item, function(_, result)
    f.resolve(result)
  end, vim.api.nvim_get_current_buf())

  local resolved = f.await(runtime.current())
  if not resolved then
    return nil
  end

  return {
    additional_text_edits = resolved.additionalTextEdits,
    command = resolved.command or meta.command,
  }
end

---@param meta completions.ItemMeta
M.exec_command = function(meta)
  if not (meta.command and meta.client_id) then
    return
  end

  local client = vim.lsp.get_client_by_id(meta.client_id)
  if not client then
    return
  end

  client:exec_cmd(meta.command, { bufnr = vim.api.nvim_get_current_buf() })
end

return M
