(function(...)
  local cancel, cur_session = nil, nil

  COQlsp_comp = function(name, session_id, pos)
    cur_session = session_id

    if cancel then
      pcall(cancel)
    end

    local n_clients = 0
    local client_names = {}
    for id, info in pairs(vim.lsp.buf_get_clients(0)) do
      n_clients = n_clients + 1
      client_names[id] = info.name
    end

    local payload = {
      method = name,
      uid = session_id,
      client = vim.NIL,
      done = true,
      reply = vim.NIL
    }

    if n_clients == 0 then
      COQlsp_notify(payload)
    else
      local row, col = unpack(pos)
      local position = {line = row, character = col}
      local text_doc = vim.lsp.util.make_text_document_params()
      local params = {
        position = position,
        textDocument = text_doc,
        context = {triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked}
      }

      local on_resp_old = function(err, _, resp, client_id)
        if session_id == cur_session then
          n_clients = n_clients - 1
          payload.client = client_names[client_id] or vim.NIL
          payload.done = n_clients == 0
          payload.reply = resp or vim.NIL
          COQlsp_notify(payload)
        end
      end

      local on_resp_new = function(err, resp, ctx)
        on_resp_old(err, nil, resp, ctx.client_id)
      end

      local on_resp = function(...)
        if type(({...})[2]) ~= "string" then
          on_resp_new(...)
        else
          on_resp_old(...)
        end
      end

      local ids = {}
      ids, cancel =
        vim.lsp.buf_request(0, "textDocument/completion", params, on_resp)
    end
  end
end)(...)
