local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local linesep = "\n"
local cancel = function () end


local notify = function (request_id, ret)
  fn._NAPnotify("lsp", request_id, ret)
end


local list_comp_candidates = function (request_id, enable_cancel, row, col)
  if enable_cancel then
    cancel()
  end

  if #lsp.buf_get_clients() == 0 then
    notify(request_id, nil)
    cancel = function () end
  else
    local position = {line = row, character = col}
    local text_doc = lsp.util.make_text_document_params()
    local params = {position = position, textDocument=text_doc}

    _, cancel = lsp.buf_request(0, "textDocument/completion", params, function (err, _, ret)
      if err then
        local e = table.concat(err, linesep)
        api.nvim_err_writeln("lsp error: " .. e .. linesep)
      end
      notify(request_id, ret)
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
