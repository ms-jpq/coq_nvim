local T = require "coq.lib.test"
local atools = require "coq.lib.atools"

local shutdown = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local async = require "coq.lib.async"
local buffers = require "coq.producers.buffers"
local commands = require "coq.commands"
local registers = require "coq.producers.registers"
local closed = false

local quit = function()
  vim.schedule(function()
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        if closed then
          io.stderr:write("VimLeavePre blocked on producer cleanup\n")
          os.exit(1)
        end
      end,
    })
    vim.cmd "qa!"
  end)
end

local new = buffers.new
buffers.new = function(...)
  local producer = new(...)
  local close = producer.close
  producer.close = function()
    local finished = async.future()
    vim.defer_fn(finished.resolve, 20)
    finished.await { cancel = false }
    close()
    closed = true
  end
  return producer
end

if during_startup then
  registers.new = function()
    quit()
    async.sleep(60000)
    error "startup was not cancelled"
  end
else
  local bind = commands.bind
  commands.bind = function(...)
    bind(...)
    quit()
  end
end

local clients = {}
for name in pairs(require("coq.config").merged().clients) do
  clients[name] = { enabled = name == "buffers" or (during_startup and name == "registers") }
end
vim.defer_fn(function()
  io.stderr:write("shutdown test timed out\n")
  os.exit(2)
end, 3000)
require("coq").setup { clients = clients }
]]

T.describe({ "coq shutdown" }, function(test)
  for _, case in ipairs {
    { name = "exits without blocking on producer cleanup", during_startup = false },
    { name = "exits during startup without blocking on producer cleanup", during_startup = true },
  } do
    test({ case.name, timeout = 5000 * T.SLOW }, function()
      local result = assert(atools.spawn {
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "-c",
        "lua local during_startup = " .. tostring(case.during_startup) .. "; " .. shutdown,
      })
      T.eq(result, { code = 0, signal = 0, stdout = "", stderr = "" })
    end)
  end
end)
