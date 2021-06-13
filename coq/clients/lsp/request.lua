(function (...)
  local cancel = function () end

  return function (request_id, pos)
    if cancel then
      cancel()
    end
    cancel = nil

    local row, col = unpack(pos)
    local position = {line = row, character = col}
    local text_doc = vim.lsp.util.make_text_document_params()
    local params = {position = position, textDocument=text_doc}

    _, cancel = vim.lsp.buf_request(0, "textDocument/completion", params, function (_, _, resp)
      COQnotify(request_id, pos, resp)
    end)
  end
end)(...)
