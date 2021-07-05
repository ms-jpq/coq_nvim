(function(...)
  local cancel = function()
  end

  COQlsp_comp = function(name, session_id, pos)
    cancel()

    local clients = {}
    for _, client in ipairs(vim.lsp.buf_get_clients(0)) do
      clients[client.id] = client.name
    end

    local n_clients = #clients
    if n_clients == 0 then
      COQlsp_notify(name, session_id, true, vim.NIL, vim.NIL)
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
          n_clients = n_clients - 1

          COQlsp_notify(
            name,
            session_id,
            n_clients == 0,
            clients[client_id] or vim.NIL,
            resp or vim.NIL
          )
          if not clients[client_id] then
            print(client_id)
            print(vim.inspect(clients))
            print(vim.inspect(resp))
          end
        end
      )
    end
  end
end)(...)

