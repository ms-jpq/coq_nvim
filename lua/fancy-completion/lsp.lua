local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local cancel = function () end
local req_id = nil

local linesep = "\n"


local notify = function (request_id, ret)
  if request_id == req_id then
    fn._FCnotify("lsp", request_id, ret)
  end
end


local list_comp_candidates = function (request_id, row, col)
  req_id = request_id
  cancel()
  cancel = function () end

  if #lsp.buf_get_clients() == 0 then
    notify(request_id, nil)
  else
    local position = {line = row, character = col}
    local text_doc = lsp.util.make_text_document_params()
    local params = {position = position, textDocument=text_doc}

    _, cancel = lsp.buf_request(0, "textDocument/completion", params, function (err, _, ret)
      if err then
        api.nvim_out_writeln("lsp error: " .. err .. linesep)
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
