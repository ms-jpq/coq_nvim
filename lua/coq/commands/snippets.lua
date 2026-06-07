local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local path_fmt = require "coq.producers.path_fmt"
local sources = require "coq.producers.snippets.sources"

local M = {}

M.SUBCMDS = { "ls", "cd", "compile", "edit" }

---@return idle.Ctx
local fake_ctx = function()
  ---@diagnostic disable-next-line: missing-fields
  return { ---@type idle.Ctx
    config_dir = vim.fn.stdpath "config",
    cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "coq"),
    rtps = vim.api.nvim_list_runtime_paths(),
  }
end

---@param settings config.Settings
local ls = function(settings)
  local cwd = lib.getcwd()
  local current = vim.api.nvim_buf_get_name(0)
  local idle_ctx = fake_ctx()

  local lines = lib.scope(function(defer)
    local close, iter = sources.list(settings, idle_ctx, nil)
    defer(close)
    return vim
      .iter(iter)
      :map(function(src)
        return "~> " .. path_fmt.fmt(cwd, src.path, current)
      end)
      :totable()
  end)

  atools.scheduled()
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param settings config.Settings
local cd = function(settings)
  local dir = sources.write_dir(settings, fake_ctx())

  atools.scheduled()
  vim.fn.mkdir(dir, "p")
  vim.cmd.cd { args = { dir }, mods = { silent = true } }
end

---@param settings config.Settings
---@param filetype string
local edit = function(settings, filetype)
  local dir = sources.write_dir(settings, fake_ctx())
  local ft = filetype ~= "" and filetype or vim.bo.filetype
  if ft == "" then
    ft = "_"
  end

  atools.scheduled()
  vim.fn.mkdir(dir, "p")
  vim.cmd.edit(vim.fs.joinpath(dir, ft .. ".snip"))
end

---@param settings config.Settings
---@param events completions.Events
---@return fun(args: string[])
M.bind = function(settings, events)
  local actions = {
    ls = function()
      ls(settings)
    end,
    cd = function()
      cd(settings)
    end,
    compile = function()
      events.idle.replace { synthetic = true }
    end,
    edit = function(rest)
      edit(settings, rest or "")
    end,
  }

  return async.entry(function(args)
    atools.scheduled()
    local action, rest = unpack(args or {})
    local handler = actions[action or "ls"]
    if handler then
      handler(rest)
    else
      vim.notify(
        string.format("COQ snips: unknown subcommand %q (expected %s)", action, table.concat(M.SUBCMDS, "/")),
        vim.log.levels.ERROR
      )
    end
  end)
end

return M
