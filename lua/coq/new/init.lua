local config = require "coq.new.config"
local supervisor = require "coq.lib.producers.supervisor"

local M = {}

---@param opts? table
M.setup = function(opts)
  local settings = config.merged(opts)
  local sup = supervisor.new {}
  return { settings = settings, supervisor = sup }
end

return M
