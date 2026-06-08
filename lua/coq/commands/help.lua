local float = require "coq.commands.float"

local URI_BASE = "https://github.com/ms-jpq/coq_nvim/tree/coq/docs/"

local M = {}

M.TOPICS = {
  index = "README",
  v2 = "V2",
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

---@param fargs string[]
M.run = function(fargs)
  local topic = "index"
  local web = false
  for _, a in pairs(fargs) do
    if a == "-w" or a == "--web" then
      web = true
    elseif M.TOPICS[a] then
      topic = a
    else
      vim.notify("COQ help: unknown arg '" .. a .. "'", vim.log.levels.ERROR)
      return
    end
  end

  local name = M.TOPICS[topic] .. ".md"

  if web then
    vim.ui.open(URI_BASE .. name)
    return
  end

  local path = vim.api.nvim_get_runtime_file("docs/" .. name, false)[1]
  if not path then
    vim.notify("COQ help: docs/" .. name .. " not on runtimepath", vim.log.levels.ERROR)
    return
  end

  float.show { ns = "coq.help", lines = vim.fn.readfile(path), filetype = "markdown" }
end

return M
