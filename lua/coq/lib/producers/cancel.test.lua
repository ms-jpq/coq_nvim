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
    close = lib.noop,
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
      -- If cancel correctly wakes the matcher, its sleep raises before
      -- matcher_completed is set. If cancel didn't wake it, the matcher would
      -- sleep its full 200ms and set the flag.
      local h = handle.new()
      local matcher_completed = false
      local n = nursery.new()
      local db = nil
      local _ = h.on_cancel(n.cancel)
      n.spawn(function()
        db = factory {
          source = "mock",
          idle = lib.noop,
          matcher = function(_, ctx)
            require("coq.lib.async").sleep(200 * ctx.slow)
            matcher_completed = true
            coroutine.yield "never"
          end,
        }
        local _, iter = db.search(SETTINGS, { slow = T.SLOW })
        pcall(iter)
      end)
      n.spawn(function()
        async.sleep(30 * T.SLOW)
        h.cancel()
      end)
      n.join()
      if db and db.close then
        db.close()
      end
      T.eq(matcher_completed, false)
    end)
  end)
end

cancel_tests("regular", regular)
cancel_tests("threaded", producer.threaded)
