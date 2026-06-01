local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local producer = require "coq.lib.producers"
local threaded = require "coq.lib.producers.threaded"

local cancel_tests = function(name, factory)
  T.describe("producer " .. name .. " :: cancel", function(test)
    test("bind cancellation is idempotent", function()
      local n = nursery.new()
      local _ = handle.new().on_cancel(n.cancel)
      local db = factory {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      db.bind(n)
      n.cancel()
      n.cancel() -- no error
    end)

    test("ambient cancel wakes a sleeping matcher", function()
      local h = handle.new()
      local elapsed_ms
      local n = nursery.new()
      local _ = h.on_cancel(n.cancel)
      n.spawn(function()
        local db = factory {
          idle = lib.noop,
          bind = lib.noop,
          matcher = function(_, ctx)
            require("coq.lib.async").sleep(200 * ctx.slow)
            coroutine.yield "never"
          end,
        }
        db.bind(n)
        local start = vim.uv.hrtime()
        pcall(db.search { slow = T.SLOW })
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

cancel_tests("regular", producer.new)
cancel_tests("threaded", threaded.new)
