(function(...)
  local cancel = nil

  COQlsp_comp = function(name, session_id, pos)
    if cancel then
      cancel()
    end

    local n_clients = 0
    for _ in pairs(vim.lsp.buf_get_clients(0)) do
      n_clients = n_clients + 1
    end

    if n_clients == 0 then
      COQlsp_notify(name, session_id, true, vim.NIL)
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
          COQlsp_notify(name, session_id, n_clients == 0, resp or vim.NIL)
        end
      )
    end
  end
end)(...)

