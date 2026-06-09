local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local json = require "coq.lib.json"
local lib = require "coq.lib"
local neosnippet = require "coq.producers.snippets.loaders.neosnippet"
local path_fmt = require "coq.producers.path_fmt"
local sources = require "coq.producers.snippets.sources"
local txt = require "coq.lib.text"

local M = {}

M.SUBCMDS = { "ls", "cd", "compile", "edit", "eval" }

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
  vim.fn.mkdir(dir, "p")
  vim.cmd.cd { args = { dir }, mods = { silent = true } }
end

local VISUAL_BLOCK = vim.keycode "<c-v>"
local ESC = vim.keycode "<esc>"

local PREVIEW_NAME = "COQ-snip-eval"

---@param lines string[]
local set_preview = function(lines)
  vim.cmd.pedit { args = { PREVIEW_NAME }, mods = { silent = true, emsg_silent = true } }
  vim.cmd.wincmd [[P]]
  local buf = vim.api.nvim_get_current_buf()

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "json"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.cmd.wincmd [[p]]
end

---@param parents string[]
---@param sourced snippets.Sourced
---@return table
local report = function(parents, sourced)
  local snippets = vim
    .iter(sourced.snippets)
    :map(function(it)
      local ok, err = pcall(vim.lsp._snippet_grammar.parse, it.body)
      return {
        label = it.label,
        match = it.word,
        status = ok and "ok" or "error",
        error = not ok and tostring(err) or nil,
        body = it.body,
      }
    end)
    :totable()
  return { extends = parents, snippets = snippets }
end

local eval = function()
  local mode = vim.fn.mode()
  local lo, hi
  if mode == "v" or mode == "V" or mode == VISUAL_BLOCK then
    vim.cmd.normal { args = { ESC }, bang = true }
    lo = vim.fn.line "'<" - 1
    hi = vim.fn.line "'>"
  else
    lo, hi = 0, -1
  end

  local lines = vim.api.nvim_buf_get_lines(0, lo, hi, false)
  local text = table.concat(lines, "\n")
  if text == "" then
    return
  end

  local src = {
    filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "_",
    path = vim.api.nvim_buf_get_name(0),
    mtime = 0,
  } --[[@as snippets.Source]]
  local perr, parents, sourced = neosnippet.parse(src, text)

  local value = perr and { error = perr } or report(parents, sourced)
  set_preview(vim.iter(txt.splitlines(json.encode(value, true))):totable())
end

---@param settings config.Settings
---@param filetype string
local edit = function(settings, filetype)
  local dir = sources.write_dir(settings, fake_ctx())
  local ft = filetype ~= "" and filetype or vim.bo.filetype
  if ft == "" then
    ft = "_"
  end
  vim.fn.mkdir(dir, "p")
  vim.cmd.edit { args = { vim.fs.joinpath(dir, ft .. ".snip") } }
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
    eval = eval,
  }

  return async.entry(function(args)
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
