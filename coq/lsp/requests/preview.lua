(function(...)
  local cancel = function()
  end

  COQlsp_preview = function(name, session_id, request_id, item)
    cancel()

    local clients = vim.lsp.buf_get_clients(0)
    if #clients == 0 then
      COQlsp_notify(name, request_id, vim.NIL)
    else
      local ids = {}
      ids, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(err, _, resp)
          if not err then
            COQlsp_notify(name, session_id, request_id, resp or vim.NIL)
          end
        end
      )
    end
  end
end)(...)

