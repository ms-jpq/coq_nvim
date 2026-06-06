local toggle = require "coq.lib.producers.toggle"

local M = {}

---@param settings config.Settings
---@return string[]
local known_sources = function(settings)
  local names = {}
  for name in pairs(settings.clients) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

M.SUBCMDS = { "on", "off", "list" }

---@param settings config.Settings
---@param fargs string[]
M.run = function(settings, fargs)
  local known = known_sources(settings)
  local known_set = {}
  for _, n in ipairs(known) do
    known_set[n] = true
  end

  if #fargs == 0 or fargs[1] == "list" then
    local on, off = {}, {}
    for _, name in ipairs(known) do
      if toggle.is_enabled(name) then
        table.insert(on, name)
      else
        table.insert(off, name)
      end
    end
    vim.notify(
      "COQsource:\n  on:  " .. table.concat(on, ", ") .. "\n  off: " .. table.concat(off, ", "),
      vim.log.levels.INFO
    )
    return
  end

  if #fargs ~= 2 then
    vim.notify("COQsource: usage — :COQsource (on|off) <source> | :COQsource list", vim.log.levels.ERROR)
    return
  end

  local cmd, name = fargs[1], fargs[2]
  if cmd ~= "on" and cmd ~= "off" then
    vim.notify("COQsource: unknown subcommand '" .. cmd .. "'", vim.log.levels.ERROR)
    return
  end
  if not known_set[name] then
    vim.notify("COQsource: unknown source '" .. name .. "'", vim.log.levels.ERROR)
    return
  end

  toggle.set(name, cmd == "on")
  vim.notify("COQsource: " .. name .. " " .. cmd, vim.log.levels.INFO)
end

---@param settings config.Settings
---@param arglead string
---@param cmdline string
---@return string[]
M.complete = function(settings, arglead, cmdline)
  local parts = vim.split(cmdline, "%s+")
  -- parts[1] = "COQsource", parts[2] = subcmd or partial, parts[3] = source or partial
  if #parts <= 2 then
    return vim
      .iter(M.SUBCMDS)
      :filter(function(t)
        return vim.startswith(t, arglead)
      end)
      :totable()
  end
  if parts[2] == "on" or parts[2] == "off" then
    return vim
      .iter(known_sources(settings))
      :filter(function(t)
        return vim.startswith(t, arglead)
      end)
      :totable()
  end
  return {}
end

return M
