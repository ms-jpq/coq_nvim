(function(...)
  local cancels = {}

  local req = function(name, session_id, clients, callback)
    local n_clients, client_names = unpack(clients)

    if cancels[name] then
      pcall(cancels[name])
    end

    local payload = {
      method = name,
      uid = session_id,
      client = vim.NIL,
      done = true,
      reply = vim.NIL
    }

    local on_resp_old = function(err, _, resp, client_id)
      n_clients = n_clients - 1
      payload.client = client_names[client_id] or vim.NIL
      payload.done = n_clients == 0
      payload.reply = resp or vim.NIL
      COQlsp_notify(payload)
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

    if n_clients == 0 then
      COQlsp_notify(payload)
    else
      local _, cancel = callback(on_resp)
      cancels[name] = cancel
    end
  end

  local lsp_clients = function()
    local n_clients = 0
    local client_names = {}
    for id, info in pairs(vim.lsp.buf_get_clients(0)) do
      n_clients = n_clients + 1
      client_names[id] = info.name
    end
    return n_clients, client_names
  end

  COQlsp_comp = function(name, session_id, pos)
    local row, col = unpack(pos)
    local position = {line = row, character = col}
    local text_doc = vim.lsp.util.make_text_document_params()
    local params = {
      position = position,
      textDocument = text_doc,
      context = {triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked}
    }
    req(
      name,
      session_id,
      {lsp_clients()},
      function(on_resp)
        return vim.lsp.buf_request(
          0,
          "textDocument/completion",
          params,
          on_resp
        )
      end
    )
  end

  COQlsp_preview = function(name, session_id, item)
    req(
      name,
      session_id,
      {lsp_clients()},
      function(on_resp)
        return vim.lsp.buf_request(0, "completionItem/resolve", item, on_resp)
      end
    )
  end

  COQlsp_third_party = function(name, session_id, pos)
    local client_names, client_fns = (function()
      local sources = COQsources or {}
      local names, fns = {}, {}

      if type(sources) == "table" then
        for id, source in pairs(sources) do
          if type(source.name) == "string" and type(source.fn) == "function" then
            names[id] = source.name
            table.insert(fns, {id, source.fn})
          end
        end
      end

      return names, fns
    end)()

    local cancels = {}
    local cancel = function()
      for _, cont in ipairs(cancels) do
        local go, err = pcall(cont)
        if not go then
          vim.api.nvim_err_writeln(err)
        end
      end
    end

    local args = {pos = pos}

    req(
      name,
      session_id,
      {client_names, client_fns},
      function(on_resp)
        for _, spec in ipairs(client_fns) do
          local id, fn = unpack(spec)
          local go, maybe_cancel =
            pcall(
            fn,
            args,
            function(resp)
              on_resp(nil, "", resp, id)
            end
          )
          if go then
            if type(maybe_cancel) == "function" then
              table.insert(cancels, maybe_cancel)
            end
          else
            vim.api.nvim_err_writeln(maybe_cancel)
          end
        end
        return {}, cancel
      end
    )
  end
end)(...)
