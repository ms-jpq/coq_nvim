local T = require "coq.lib.test"
local async = require "coq.lib.async"
local config = require "coq.config"
local handle = require "coq.lib.async._handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async._nursery"
local producer = require "coq.lib.producers"

local SETTINGS = config.merged()

---@param spec producers.Spec
---@return producers.Producer
local regular = function(spec)
  return {
    source = "mock",
    idle = lib.noop,
    search = function(settings, ctx)
      local iter = async.wrap(function()
        spec.matcher(settings, ctx)
      end)
      return setmetatable({ close = lib.noop }, { __call = iter })
    end,
  }
end

local cancel_tests = function(name, factory)
  T.describe({ "producer " .. name .. " :: cancel" }, function(test)
    test({ "ambient cancel wakes a sleeping matcher" }, function()
      local h = handle.new()
      local elapsed_ms
      local n = nursery.new()
      local _ = h.on_cancel(n.cancel)
      n.spawn(function()
        local db = factory {
          source = "mock",
          idle = lib.noop,
          matcher = function(_, ctx)
            require("coq.lib.async").sleep(200 * ctx.slow)
            coroutine.yield "never"
          end,
        }
        local start = vim.uv.hrtime()
        local _, iter = db.search(SETTINGS, { slow = T.SLOW })
        pcall(iter)
        elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      end)
      n.spawn(function()
        async.sleep(30 * T.SLOW)
        h.cancel()
      end)
      n.join()
      assert(elapsed_ms and elapsed_ms < 100 * T.SLOW, ("expected fast wake, got %s ms"):format(tostring(elapsed_ms)))
    end)
  end)
end

cancel_tests("regular", regular)
cancel_tests("threaded", producer.threaded)
