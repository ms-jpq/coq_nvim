(function(...)
  local freeze = function(name, is_list, original)
    vim.validate {
      name = {name, "string"},
      is_list = {is_list, "boolean"},
      original = {original, "table"}
    }

    local proxy =
      setmetatable(
      is_list and original or {},
      {
        __index = function(_, key)
          if original[key] == nil then
            error("NotImplementedError :: " .. name .. "->" .. key)
          else
            return original[key]
          end
        end,
        __newindex = function(_, key, val)
          error(
            "TypeError :: " ..
              vim.inspect {key, val} .. "->frozen<" .. name .. ">"
          )
        end
      }
    )
    return proxy
  end

  local req =
    (function()
    local cancels = {}
    return function(name, session_id, clients, callback)
      local n_clients, client_names = unpack(clients)
      vim.validate {
        name = {name, "string"},
        session_id = {session_id, "number"},
        n_clients = {n_clients, "number"},
        client_names = {client_names, "table"},
        callback = {callback, "function"}
      }

      pcall(
        cancels[name] or function()
          end
      )

      local payload = {
        name = name,
        method = vim.NIL,
        uid = session_id,
        client = vim.NIL,
        done = true,
        reply = vim.NIL
      }

      local on_resp_old = function(err, method, resp, client_id)
        n_clients = n_clients - 1
        payload.method = method
        payload.client = client_names[client_id] or vim.NIL
        payload.done = n_clients == 0
        payload.reply = resp or vim.NIL
        COQ.Lsp_notify(payload)
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
        COQ.Lsp_notify(payload)
      else
        local _, cancel = callback(on_resp)
        cancels[name] = cancel
      end
    end
  end)()

  local lsp_clients = function()
    local n_clients = 0
    local client_names = {}
    for id, info in pairs(vim.lsp.buf_get_clients(0)) do
      n_clients = n_clients + 1
      client_names[id] = info.name
    end
    return n_clients, client_names
  end

  COQ.lsp_comp = function(name, session_id, pos)
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

  COQ.lsp_resolve = function(name, session_id, item)
    req(
      name,
      session_id,
      {lsp_clients()},
      function(on_resp)
        return vim.lsp.buf_request(0, "completionItem/resolve", item, on_resp)
      end
    )
  end

  COQ.lsp_command = function(name, session_id, cmd)
    req(
      name,
      session_id,
      {lsp_clients()},
      function(on_resp)
        return vim.lsp.buf_request(0, "workspace/executeCommand", cmd, on_resp)
      end
    )
  end

  local lua_clients = function()
    local sources = COQsources or {}
    local names, fns = {}, {}

    if type(sources) == "table" then
      for id, source in pairs(sources) do
        if
          type(source) == "table" and type(source.name) == "string" and
            type(source.fn) == "function"
         then
          names[id] = source.name
          table.insert(fns, {id, source.fn})
        end
      end
    end

    return names, fns
  end

  local lua_cancel = function()
    local acc = {}
    local cancel = function()
      for _, cont in ipairs(acc) do
        local go, err = pcall(cont)
        if not go then
          vim.api.nvim_err_writeln(err)
        end
      end
    end
    return acc, cancel
  end

  local lua_req = function(method, args)
    local client_names, client_fns = lua_clients()
    local cancels, cancel = lua_cancel()
    req(
      name,
      session_id,
      {#client_fns, client_names},
      function(on_resp)
        for _, spec in ipairs(client_fns) do
          local id, fn = unpack(spec)
          local go, maybe_cancel =
            pcall(
            fn,
            args,
            function(resp)
              on_resp(nil, method, resp, id)
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

  COQ.lsp_third_party = function(name, session_id, pos, line)
    local args =
      freeze(
      "coq_3p.args",
      false,
      {
        uid = session_id,
        pos = freeze("coq_3p.args.pos", true, pos),
        line = line
      }
    )

    lua_req("< lua :: comp >", args)
  end
end)(...)
