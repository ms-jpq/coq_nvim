local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local cancel = nil


local list_comp_candidates = function (request_id, row, col)
  if cancel then
    cancel()
    cancel = nil
  end

  if #lsp.buf_get_clients() == 0 then
    fn._FCnotify("lsp", request_id, nil)
  else
    local position = {line = row, character = col}
    local text_doc = lsp.util.make_text_document_params()
    local params = {position = position, textDocument=text_doc}

    _, cancel = lsp.buf_request(0, "textDocument/completion", params, function (err, _, ans)
      if err then
        api.nvim_err_writeln(err)
      end
      local ret = ans or nil
      fn._FCnotify("lsp", request_id, ret)
    end)
  end
end


local list_entry_kind = function ()
  local tb = {}
  for k, v in pairs(lsp.protocol.CompletionItemKind) do
    if type(k) == "string" and type(v) == "number" then
      tb[k] = v
    end
  end
  return tb
end


local list_insert_kind = function ()
  local tb = {}
  for k, v in pairs(lsp.protocol.InsertTextFormat) do
    if type(k) == "string" and type(v) == "number" then
      tb[k] = v
    end
  end
  return tb
end


return {
  list_comp_candidates = list_comp_candidates,
  list_entry_kind = list_entry_kind,
  list_insert_kind = list_insert_kind,
}
