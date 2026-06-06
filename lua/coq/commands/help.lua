local float = require "coq.commands.float"

local TOPICS = {
  index = "README",
  config = "CONF",
  keybind = "KEYBIND",
  snips = "SNIPS",
  fuzzy = "FUZZY",
  comp = "COMPLETION",
  display = "DISPLAY",
  sources = "SOURCES",
  misc = "MISC",
  stats = "STATS",
  perf = "PERF",
  custom_sources = "CUSTOM_SOURCES",
}

local URI_BASE = "https://github.com/ms-jpq/coq_nvim/tree/coq/docs/"

local M = {}

---@param fargs string[]
M.run = function(fargs)
  local topic = "index"
  local web = false
  for _, a in pairs(fargs) do
    if a == "-w" or a == "--web" then
      web = true
    elseif TOPICS[a] then
      topic = a
    else
      vim.notify("COQhelp: unknown arg '" .. a .. "'", vim.log.levels.ERROR)
      return
    end
  end

  local name = TOPICS[topic] .. ".md"
  if web then
    vim.ui.open(URI_BASE .. name)
    return
  end

  local found = vim.api.nvim_get_runtime_file("docs/" .. name, false)
  local path = found[1]
  if not path then
    vim.notify("COQhelp: docs/" .. name .. " not on runtimepath", vim.log.levels.ERROR)
    return
  end

  local lines = vim.fn.readfile(path)
  float.show { ns = "coq.help", lines = lines, filetype = "markdown" }
end

---@return string[]
M.complete = function()
  return vim.tbl_keys(TOPICS)
end

return M
