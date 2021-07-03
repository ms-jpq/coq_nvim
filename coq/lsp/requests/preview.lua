(function(...)
  local cancel = function()
  end

  COQlsp_preview = function(name, session_id, item)
    cancel()

    local clients = {}
    for _, client in ipairs(vim.lsp.buf_get_clients(0)) do
      clients[client.id] = client.name
    end

    if #clients == 0 then
      COQlsp_notify(name, session_id, vim.NIL)
    else
      local ids = {}
      ids, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(err, _, resp, client_id)
          if not err then
            COQlsp_notify(name, session_id, client_id, resp or vim.NIL)
          end
        end
      )
    end
  end
end)(...)

