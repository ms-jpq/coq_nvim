return function(args)
  local cwd = unpack(args)
  local is_win = vim.api.nvim_call_function("has", {"win32"}) == 1

  local function defer(timeout, callback)
    local timer = vim.loop.new_timer()
    timer:start(
      timeout,
      0,
      function()
        timer:stop()
        timer:close()
        vim.schedule(callback)
      end
    )
    return timer
  end

  coq = coq or {}
  local linesep = "\n"
  local POLLING_RATE = 10

  if coq.loaded then
    return
  else
    coq.loaded = true
    local job_id = nil
    local coq_params = {}
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
      for _, param in ipairs(coq_params) do
        coq[coq_params] = nil
      end
    end

    local on_stdout = function(_, msg)
      vim.api.nvim_out_write(table.concat(msg, linesep))
    end

    local on_stderr = function(_, msg)
      vim.api.nvim_err_write(table.concat(msg, linesep))
    end

    local main = function()
      local go, _py3 = pcall(vim.api.nvim_get_var, "python3_host_prog")
      local py3 = go and _py3 or (is_win and "python" or "python3")
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

    local start = function(...)
      local args =
        vim.tbl_flatten {
        main(),
        {"-m", "coq"},
        {...}
      }

      local params = {
        cwd = cwd,
        on_exit = on_exit,
        on_stdout = on_stdout,
        on_stderr = on_stderr,
      }
      local job_id = vim.fn.jobstart(args, params)
      return job_id
    end

    coq.deps_cmd = function()
      start("deps")
    end

    vim.api.nvim_command [[command! -nargs=0 COQdeps lua coq.deps_cmd()]]

    local set_coq_call = function(name, cmd)
      table.insert(coq_params, name)

      coq[name] = function(...)
        local args = {...}

        if not job_id then
          local server = vim.api.nvim_call_function("serverstart", {})
          job_id = start("run", "--socket", server)
        end

        if not err_exit and _G[cmd] then
          _G[cmd](args)
        else
          defer(
            POLLING_RATE,
            function()
              if err_exit then
                return
              else
                coq[name](unpack(args))
              end
            end
          )
        end
      end
    end

    set_coq_call("open_cmd", "coqopen")
    vim.api.nvim_command [[command! -nargs=* COQopen lua coq.open_cmd(<f-args>)]]

    set_coq_call("help_cmd", "coqhelp")
    vim.api.nvim_command [[command! -nargs=* COQhelp lua coq.help_cmd(<f-args>)]]
  end
end
