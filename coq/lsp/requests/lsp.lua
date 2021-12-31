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

  local lsp_clients = function(client_names, buf, lsp_method)
    vim.validate {client_names = {client_names, "table"}}

    local filter = (function()
      if #client_names <= 0 then
        return function()
          return true
        end
      else
        local acc = {}
        for _, client_name in ipairs(client_names) do
          vim.validate {client_name = {client_name, "string"}}
          acc[client_name] = true
        end

        return function(client_name)
          vim.validate {client_name = {client_name, "string"}}
          return acc[client_name]
        end
      end
    end)()

    vim.validate {
      buf = {buf, "number"},
      lsp_method = {lsp_method, "string"},
      filter = {filter, "function"}
    }

    local n_clients = 0
    local clients = {}

    for id, client in pairs(vim.lsp.buf_get_clients(buf)) do
      if filter(client.name) and client.supports_method(lsp_method) then
        n_clients = n_clients + 1
        clients[id] = client
      end
    end

    return n_clients, clients
  end

  local lsp_request_all = function(clients, buf, lsp_method, params, handler)
    vim.validate {
      buf = {buf, "number"},
      clients = {clients, "table"},
      lsp_method = {lsp_method, "string"},
      handler = {handler, "function"}
    }

    local cancels = {}
    local cancel_all = function()
      for _, cancel in ipairs(cancels) do
        cancel()
      end
    end

    for _, client in pairs(clients) do
      vim.validate {
        client = {client, "table"}
      }

      local go, cancel_handle = client.request(lsp_method, params, handler, buf)
      if not go then
        handler("<>FAILED<>", nil, {client_id = client.id, method = lsp_method})
      else
        table.insert(
          cancels,
          function()
            client.cancel_request(cancel_handle)
          end
        )
      end
    end

    return cancel_all
  end

  local req =
    (function()
    local cancels = {}
    return function(name, session_id, clients, callback)
      vim.validate {
        clients = {clients, "table"}
      }
      local n_clients, client_map = unpack(clients)
      vim.validate {
        name = {name, "string"},
        session_id = {session_id, "number"},
        n_clients = {n_clients, "number"},
        client_map = {client_map, "table"},
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
        vim.validate {
          method = {method, "string", true},
          client_id = {client_id, "number", true}
        }

        n_clients = n_clients - 1
        payload.method = method or vim.NIL
        payload.client = (function()
          local client = client_map[client_id]
          return client and client.name or vim.NIL
        end)()
        payload.done = n_clients == 0
        payload.reply = resp or vim.NIL
        COQ.Lsp_notify(payload)
      end

      local on_resp_new = function(err, resp, ctx)
        on_resp_old(err, ctx.method, resp, ctx.client_id)
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
        cancels[name] = callback(on_resp)
      end
    end
  end)()

  COQ.lsp_comp = function(name, session_id, client_names, pos)
    vim.validate {
      name = {name, "string"},
      session_id = {session_id, "number"},
      client_names = {client_names, "table"},
      pos = {pos, "table"}
    }

    local row, col = unpack(pos)
    vim.validate {
      row = {row, "number"},
      col = {col, "number"}
    }

    local position = {line = row, character = col}
    local text_doc = vim.lsp.util.make_text_document_params()
    local params = {
      position = position,
      textDocument = text_doc,
      context = {triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked}
    }

    local buf = vim.api.nvim_get_current_buf()
    local lsp_method = "textDocument/completion"
    local n_clients, clients = lsp_clients({}, buf, lsp_method)

    req(
      name,
      session_id,
      {n_clients, clients},
      function(on_resp)
        return lsp_request_all(clients, buf, lsp_method, params, on_resp)
      end
    )
  end

  COQ.lsp_resolve = function(name, session_id, client_names, item)
    vim.validate {
      name = {name, "string"},
      session_id = {session_id, "number"},
      client_names = {client_names, "table"},
      item = {item, "table"}
    }

    local buf = vim.api.nvim_get_current_buf()
    local lsp_method = "completionItem/resolve"
    local n_clients, clients = lsp_clients(client_names, buf, lsp_method)

    req(
      name,
      session_id,
      {n_clients, clients},
      function(on_resp)
        return lsp_request_all(clients, buf, lsp_method, item, on_resp)
      end
    )
  end

  COQ.lsp_command = function(name, session_id, client_names, cmd)
    vim.validate {
      name = {name, "string"},
      session_id = {session_id, "number"},
      client_names = {client_names, "table"},
      cmd = {cmd, "table"}
    }
    vim.validate {
      command = {cmd.command, "string"}
    }

    local buf = vim.api.nvim_get_current_buf()
    local lsp_method = "workspace/executeCommand"
    local n_clients, clients = lsp_clients({}, buf, lsp_method)

    req(
      name,
      session_id,
      {n_clients, clients},
      function(on_resp)
        return lsp_request_all(clients, buf, lsp_method, cmd, on_resp)
      end
    )
  end

  local lua_clients = function(key)
    vim.validate {key = {key, "string"}}

    local sources = COQsources or {}
    local names, fns = {}, {}

    if type(sources) == "table" then
      for id, source in pairs(sources) do
        if
          type(source) == "table" and type(source.name) == "string" and
            type(source[key]) == "function"
         then
          names[id] = {name = source.name}
          table.insert(fns, {id, source[key]})
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

  local lua_req = function(name, session_id, key, method, args)
    vim.validate {
      name = {name, "string"},
      session_id = {session_id, "number"},
      key = {key, "string"},
      method = {method, "string"},
      args = {args, "table"}
    }

    local client_names, client_fns = lua_clients(key)
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
        return cancel
      end
    )
  end

  COQ.lsp_third_party = function(name, session_id, client_names, pos, line)
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

    lua_req(name, session_id, "fn", "< lua :: comp >", args)
  end

  COQ.lsp_third_party_resolve = function(name, session_id, client_names, item)
    local args =
      freeze(
      "coq_3p.args",
      false,
      {
        uid = session_id,
        item = item
      }
    )

    lua_req(name, session_id, "resolve", "< lua :: resolve >", args)
  end

  COQ.lsp_third_party_cmd = function(name, session_id, client_names, cmd)
    local args =
      freeze(
      "coq_3p.args",
      false,
      {
        uid = session_id,
        command = cmd.command,
        arguments = cmd.arguments
      }
    )

    lua_req(name, session_id, "exec", "< lua :: cmd >", args)
  end
end)(...)
