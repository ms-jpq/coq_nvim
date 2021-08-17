return function(args)
  local seek_rtp = function()
    local name = "coq_nvim"
    for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
      if string.sub(rtp, -(#name)) == name then
        return rtp
      end
    end
    assert(false, "RTP NOT FOUND")
  end
  local cwd = args and unpack(args) or seek_rtp()

  coq = coq or {}
  local linesep = "\n"
  local POLLING_RATE = 10

  if coq.loaded then
    return coq
  else
    local is_win = vim.api.nvim_call_function("has", {"win32"}) == 1

    coq.loaded = true
    local job_id = nil
    local err_exit = false

    local on_exit = function(_, code)
      local msg = " | COQ EXITED - " .. code
      if not (code == 0 or code == 143) then
        err_exit = true
        vim.api.nvim_err_writeln(msg)
      else
        err_exit = false
      end
      job_id = nil
    end

    local on_stdout = function(_, msg)
      vim.api.nvim_out_write(table.concat(msg, linesep))
    end

    local on_stderr = function(_, msg)
      vim.api.nvim_err_write(table.concat(msg, linesep))
    end

    local go, _py3 = pcall(vim.api.nvim_get_var, "python3_host_prog")
    local py3 = go and _py3 or (is_win and "python" or "python3")

    local main = function()
      local v_py =
        cwd ..
        (is_win and [[/.vars/runtime/Scripts/python.exe]] or
          "/.vars/runtime/bin/python3")
      local win_proxy = cwd .. [[/win.bat]]

      if is_win then
        if vim.fn.filereadable(v_py) == 1 then
          return {v_py}
        else
          return {win_proxy, py3}
        end
      else
        if vim.fn.filereadable(v_py) == 1 then
          return {v_py}
        else
          return {py3}
        end
      end
    end

    local start = function(deps, ...)
      local args =
        vim.tbl_flatten {
        deps and py3 or main(),
        {"-m", "coq"},
        {...}
      }

      local params = {
        cwd = cwd,
        on_exit = on_exit,
        on_stdout = on_stdout,
        on_stderr = on_stderr
      }
      job_id = vim.fn.jobstart(args, params)
      return job_id
    end

    coq.COQdeps = function()
      start(true, "deps")
    end

    vim.api.nvim_command [[command! -nargs=0 COQdeps lua coq.COQdeps()]]

    local set_coq_call = function(cmd)
      coq[cmd] = function(...)
        local args = {...}

        if not job_id then
          local server = vim.api.nvim_call_function("serverstart", {})
          job_id = start(false, "run", "--socket", server)
        end

        if not err_exit and _G[cmd] then
          _G[cmd](args)
        else
          vim.defer_fn(
            function()
              if err_exit then
                return
              else
                coq[cmd](unpack(args))
              end
            end,
            POLLING_RATE
          )
        end
      end
    end

    set_coq_call("COQnow")
    vim.api.nvim_command [[command! -nargs=* COQnow lua coq.COQnow(<f-args>)]]

    set_coq_call("COQstats")
    vim.api.nvim_command [[command! -nargs=* COQstats lua coq.COQstats(<f-args>)]]

    set_coq_call("COQhelp")
    vim.api.nvim_command [[command! -nargs=* COQhelp lua coq.COQhelp(<f-args>)]]

    coq.lsp_ensure_capabilities = function(cfg)
      local spec1 = {
        capabilities = vim.lsp.protocol.make_client_capabilities()
      }
      local spec2 = {
        capabilities = {
          textDocument = {
            completion = {
              completionItem = {
                snippetSupport = true
              }
            }
          }
        }
      }
      local maps = (cfg or {}).capabilities and {spec2} or {spec1, spec2}
      local new =
        vim.tbl_deep_extend("force", cfg or vim.empty_dict(), unpack(maps))
      return new
    end
  end

  local settings = vim.g.coq_settings or {}
  if settings.auto_start then
    coq.COQnow()
  end

  return coq
end
