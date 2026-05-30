---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local nursery = require "coq.lib.async.nursery"
local producer = require "coq.lib.producers"
local threaded = require "coq.lib.producers.threaded"

local cancel_tests = function(name, factory)
  T.describe("producer " .. name .. " :: cancel", function(test)
    test("ambient cancelled before pull returns nil", function()
      local h = handle.new()
      h.cancel()
      local got = "unset"
      async.scope(function(n)
        n.spawn(function()
          local db = factory {
            idle = lib.noop,
            bind = lib.noop,
            matcher = function()
              coroutine.yield "lil"
            end,
          }
          db.bind(n)
          got = db.search {}()
        end)
      end, h)
      T.eq(got, nil)
    end)

    test("bind cancellation is idempotent", function()
      local n = nursery.new(handle.new())
      local db = factory {
        idle = lib.noop,
        bind = lib.noop,
        matcher = function()
          coroutine.yield "lil"
        end,
      }
      db.bind(n)
      n.handle.cancel()
      n.handle.cancel() -- no error
    end)

    test("ambient cancel wakes a sleeping matcher", function()
      local h = handle.new()
      local elapsed_ms
      async.scope(function(n)
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
          local _ = db.search { slow = T.SLOW }()
          elapsed_ms = (vim.uv.hrtime() - start) / 1e6
        end)
        async.sleep(30 * T.SLOW)
        h.cancel()
      end, h)
      assert(elapsed_ms and elapsed_ms < 100 * T.SLOW, ("expected fast wake, got %s ms"):format(tostring(elapsed_ms)))
    end)
  end)
end

cancel_tests("regular", producer.new)
cancel_tests("threaded", threaded.new)
