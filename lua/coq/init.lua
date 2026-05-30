if not os.getenv "COQ_V2" then
  return require "coq.legacy.coq"
end

local async = require "coq.lib.async"
local config = require "coq.config"
local insertion = require "coq.completions.insertion"
local nursery = require "coq.lib.async.nursery"
local nvim_options = require "coq.nvim_options"
local preview = require "coq.completions.preview"
local supervisor = require "coq.lib.producers.supervisor"
local trigger = require "coq.completions.trigger"

local M = {}

---@param settings config.Settings
---@return fun(): producers.Producer?
local producers = function(settings)
  return coroutine.wrap(function()
    local clients = settings.clients

    if clients.buffers.enabled then
      coroutine.yield(require "coq.producers.buffer")
    end
  end)
end

---@param opts? table
M.setup = function(opts)
  local settings = config.merged(opts)
  nvim_options.apply(settings)
  local p = vim.iter(producers(settings)):totable()
  local sup = supervisor.new(p)

  async.entry(function()
    nursery.scope(function(n)
      sup.bind(n)
      trigger.bind(n, sup)
      preview.bind(n, settings)
      insertion.bind(n)
    end)
  end)()

  return { settings = settings, supervisor = sup }
end

return M
