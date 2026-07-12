local toggle = require "coq.lib.producers.toggle"

local M = {}

M.SUBCMDS = { "on", "off", "list" }

---@param settings config.Settings
---@return string[]
local known_sources = function(settings)
  return vim.iter(vim.tbl_keys(settings.clients)):totable()
end

---@param settings config.Settings
local list = function(settings)
  local on, off = {}, {}
  for _, name in pairs(known_sources(settings)) do
    table.insert(toggle.is_enabled(name) and on or off, name)
  end
  table.sort(on)
  table.sort(off)
  vim.notify(
    "COQsource:\n  on:  " .. table.concat(on, ", ") .. "\n  off: " .. table.concat(off, ", "),
    vim.log.levels.INFO
  )
end

---@param settings config.Settings
---@param fargs string[]
M.run = function(settings, fargs)
  local cmd, name = fargs[1] or "list", fargs[2]

  if cmd == "list" then
    list(settings)
  elseif (cmd == "on" or cmd == "off") and name and settings.clients[name] then
    toggle.set(name, cmd == "on")
    vim.notify("COQsource: " .. name .. " " .. cmd, vim.log.levels.INFO)
  else
    vim.notify("COQsource: usage — :COQ source (on|off) <source> | :COQ source list", vim.log.levels.ERROR)
  end
end

---@param settings config.Settings
---@param arglead string
---@param cmdline string
---@return string[]
M.complete = function(settings, arglead, cmdline)
  local parts = vim.split(cmdline, "%s+")
  local candidates = (#parts <= 2 and M.SUBCMDS)
    or (#parts == 3 and not vim.endswith(cmdline, " ") and M.SUBCMDS)
    or ((parts[3] == "on" or parts[3] == "off") and known_sources(settings))
    or {}
  return vim
    .iter(candidates)
    :filter(function(t)
      return vim.startswith(t, arglead)
    end)
    :totable()
end

return M
