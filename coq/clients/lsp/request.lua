(function(...)
  local cancel = function()
  end
  local session = nil

  COQlsp_req = function(request_id, session_id, pos)
    if cancel and session ~= session_id then
      cancel()
    end
    session = session_id
    cancel = nil

    local clients = vim.lsp.buf_get_clients(0)
    if #clients == 0 then
      COQnotify(request_id, vim.NIL)
    else
      local row, col = unpack(pos)
      local position = {line = row, character = col}
      local text_doc = vim.lsp.util.make_text_document_params()
      local params = {position = position, textDocument = text_doc}

      local _ = nil
      _, cancel =
        vim.lsp.buf_request(
        0,
        "textDocument/completion",
        params,
        function(_, _, resp)
          COQnotify(request_id, resp or vim.NIL)
        end
      )
    end
  end
end)(...)

