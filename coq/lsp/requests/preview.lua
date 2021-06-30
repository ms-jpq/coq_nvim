(function(...)
  local cancel = function()
  end

  COQlsp_preview = function(name, request_id, item)
    cancel()

    local clients = vim.lsp.buf_get_clients(0)
    if #clients == 0 then
      COQlsp_notify(name, request_id, vim.NIL)
    else
      local _ = nil
      _, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(_, _, resp)
          COQlsp_notify(name, request_id, resp or vim.NIL)
        end
      )
    end
  end
end)(...)

