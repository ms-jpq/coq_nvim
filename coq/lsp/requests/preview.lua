(function(...)
  local cancel = function()
  end

  COQlsp_preview_req = function(request_id, item)
    if cancel then
      cancel()
    end
    cancel = nil

    local clients = vim.lsp.buf_get_clients(0)
    if #clients == 0 then
      COQnotify(request_id, vim.NIL)
    else
      local _ = nil
      _, cancel =
        vim.lsp.buf_request(
        0,
        "completionItem/resolve",
        item,
        function(_, _, resp)
          COQnotify(request_id, resp or vim.NIL)
        end
      )
    end
  end
end)(...)


