return function(args)
  local sfile = unpack(args)
  local filepath = "/plugin/kok.vim"
  local top_lv = string.sub(sfile, 2, #sfile - #filepath)

  kok = kok or {}
  local linesep = "\n"
  local POLLING_RATE = 10

  if kok.loaded then
    return
  else
    kok.loaded = true
    local job_id = nil
    local kok_params = {}
    local err_exit = false

    local start = function(...)
      local cwd = "/" .. top_lv
      local args =
        vim.tbl_flatten {
        {"python3", "-m", "kok"},
        {...}
      }
      local params = {
        cwd = cwd,
        on_exit = function(_, code)
          local msg = " | KoK EXITED - " .. code
          if not (code == 0 or code == 143) then
            err_exit = true
            vim.api.nvim_err_writeln(msg)
          end
          job_id = nil
          for _, param in ipairs(kok_params) do
            kok[kok_params] = nil
          end
        end,
        on_stdout = function(_, msg)
          vim.api.nvim_out_write(table.concat(msg, linesep))
        end,
        on_stderr = function(_, msg)
          vim.api.nvim_err_write(table.concat(msg, linesep))
        end
      }
      local job_id = vim.api.nvim_call_function("jobstart", {args, params})
      return job_id
    end

    kok.deps_cmd = function()
      start("deps")
    end

    vim.api.nvim_command [[command! -nargs=0 KoKdeps lua KoK.deps_cmd()]]

    local set_kok_call = function(name, cmd)
      table.insert(kok_params, name)
      kok[name] = function(...)
        local args = {...}

        if not job_id then
          local server = vim.api.nvim_call_function("serverstart", {})
          job_id = start("run", "--socket", server)
        end

        if not err_exit and _G[cmd] then
          _G[cmd](args)
        else
          vim.defer(
            function()
              if err_exit then
                return
              else
                kok[name](unpack(args))
              end
            end,
            POLLING_RATE
          )
        end
      end
    end

    set_kok_call("open_cmd", "KoKopen")
    vim.api.nvim_command [[command! -nargs=* KoKopen lua KoK.open_cmd(<f-args>)]]

    set_kok_call("help_cmd", "KoKhelp")
    vim.api.nvim_command [[command! -nargs=* KoKhelp lua KoK.help_cmd(<f-args>)]]
  end
end
