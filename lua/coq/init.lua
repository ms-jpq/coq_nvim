if not os.getenv "COQ_V2" then
  return require "coq.legacy.coq"
end

local config = require "coq.config"
local nvim_options = require "coq.nvim_options"
local supervisor = require "coq.lib.producers.supervisor"

local M = {}

---@param opts? table
M.setup = function(opts)
  local settings = config.merged(opts)
  nvim_options.apply(settings)
  local sup = supervisor.new {}
  return { settings = settings, supervisor = sup }
end

return M
