(function(...)
  local cancel = function()
  end

  COQlsp_comp = function(name, session_id, pos)
    cancel()

    local clients = {}
    for _, client in ipairs(vim.lsp.buf_get_clients(0)) do
      clients[client.id] = client.name
    end

    if #clients == 0 then
      COQlsp_notify(name, session_id, vim.NIL)
    else
      local row, col = unpack(pos)
      local position = {line = row, character = col}
      local text_doc = vim.lsp.util.make_text_document_params()
      local params = {position = position, textDocument = text_doc}

      local ids = {}
      ids, cancel =
        vim.lsp.buf_request(
        0,
        "textDocument/completion",
        params,
        function(err, _, resp, client_id)
          if not err then
            COQlsp_notify(name, session_id, client_id, resp or vim.NIL)
          end
        end
      )
    end
  end
end)(...)

