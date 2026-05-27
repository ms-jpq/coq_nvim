if not os.getenv "COQ_V2" then
  return require "coq.legacy.coq"
end

local config = require "coq.config"
local keymap = require "coq.keymap"
local supervisor = require "coq.lib.producers.supervisor"

local M = {}

---@param opts? table
M.setup = function(opts)
  local settings = config.merged(opts)
  keymap.apply(settings.keymap)
  local sup = supervisor.new {}
  return { settings = settings, supervisor = sup }
end

return M
