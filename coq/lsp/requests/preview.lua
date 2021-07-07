(function(...)
  local cancel = function()
  end

  COQlsp_preview = function(name, session_id, item)
    if cancel then
      cancel()
    end

    local n_clients = #vim.lsp.buf_get_clients(0)
    if n_clients == 0 then
      COQlsp_notify(name, session_id, true, vim.NIL)
    else
      local ids = {}
      ids, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(err, _, resp, client_id)
          n_clients = n_clients - 1
          COQlsp_notify(name, session_id, n_clients == 0, resp or vim.NIL)
        end
      )
    end
  end
end)(...)

