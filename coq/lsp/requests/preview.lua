(function(...)
  local cancel = function()
  end

  COQlsp_preview = function(name, item)
    cancel()

    local clients = vim.lsp.buf_get_clients(0)
    if #clients == 0 then
      COQlsp_notify(name, vim.NIL)
    else
      local _ = nil
      _, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(_, _, resp)
          COQlsp_notify(name, resp or vim.NIL)
        end
      )
    end
  end
end)(...)

