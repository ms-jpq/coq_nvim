COQ = COQ or {}
coq = coq or {}

local is_win = vim.fn.has("win32") == 1
local linesep = "\n"
local POLLING_RATE = 10

local cwd = (function()
  local source = debug.getinfo(2, "S").source
  local file = string.match(source, "^@(.*)")
  return vim.fn.fnamemodify(file, ":p:h:h")
end)()

local job_id = nil
local err_exit = false

local on_exit = function(_, code)
  if not (code == 0 or code == 143) then
    err_exit = true
    vim.api.nvim_err_writeln("COQ EXITED - " .. code)
  else
    err_exit = false
  end
  job_id = nil
end

local on_stdout = function(_, msg)
  vim.api.nvim_out_write(table.concat(msg, linesep))
end

local on_stderr = function(_, msg)
  vim.api.nvim_echo({{table.concat(msg, linesep), "ErrorMsg"}}, true, {})
end

local py3 = vim.g.python3_host_prog or (is_win and "python" or "python3")
local xdg_dir = vim.fn.stdpath("data")

local main = function(is_xdg)
  local v_py =
    cwd ..
    (is_win and [[/.vars/runtime/Scripts/python.exe]] or
      "/.vars/runtime/bin/python3")

  if is_win then
    local v_py_xdg = xdg_dir .. "/coqrt/Scripts/python"
    local v_py = is_xdg and v_py_xdg or v_py
    if vim.fn.filereadable(v_py) == 1 then
      return {v_py}
    else
      local win_proxy = cwd .. [[/venv.bat]]
      return {win_proxy, py3}
    end
  else
    local v_py_xdg = xdg_dir .. "/coqrt/bin/python3"
    local v_py = is_xdg and v_py_xdg or v_py
    if vim.fn.filereadable(v_py) == 1 then
      return {v_py}
    else
      return {py3}
    end
  end
end

local start = function(deps, ...)
  local is_xdg = (vim.g.coq_settings or {}).xdg
  local args =
    vim.tbl_flatten {
    deps and py3 or main(is_xdg),
    {"-m", "coq"},
    {...},
    (is_xdg and {"--xdg", xdg_dir} or {})
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

coq.deps = function()
  start(true, "deps")
end

vim.api.nvim_command [[command! -nargs=0 COQdeps lua coq.deps()]]

local set_coq_call = function(cmd)
  coq[cmd] = function(...)
    local args = {...}

    if not job_id then
      job_id = start(false, "run", "--socket", vim.fn.serverstart())
    end

    if not err_exit and COQ[cmd] then
      COQ[cmd](args)
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

set_coq_call("Now")
vim.api.nvim_command [[command! -complete=customlist,coq#complete_now -nargs=* COQnow lua coq.Now(<f-args>)]]

set_coq_call("Stats")
vim.api.nvim_command [[command! -nargs=* COQstats lua coq.Stats(<f-args>)]]

set_coq_call("Snips")
vim.api.nvim_command [[command! -complete=customlist,coq#complete_snips -nargs=* COQsnips lua coq.Snips(<f-args>)]]

set_coq_call("Help")
vim.api.nvim_command [[command! -complete=customlist,coq#complete_help -nargs=* COQhelp lua coq.Help(<f-args>)]]

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

local settings = vim.g.coq_settings or {}
if settings.auto_start then
  local args = settings.auto_start == "shut-up" and {"--shut-up"} or {}
  coq.Now(unpack(args))
end

setmetatable(
  coq,
  {
    __call = function()
      return coq
    end
  }
)

return coq
