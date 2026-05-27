---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local lib = require "coq.lib"
local producer = require "coq.lib.producer"
local threaded = require "coq.lib.producer.threaded"

local cancel_tests = function(name, factory)
  T.describe("producer " .. name .. " :: cancel", function(test)
    test("ambient cancelled before pull returns nil", function()
      local h = handle.new()
      h.cancel()
      local got = "unset"
      async.scope(function(n)
        n.spawn(function()
          local db = factory(lib.noop, function()
            coroutine.yield "lil"
          end)
          got = db.search {}()
          db.close()
        end)
      end, h)
      T.eq(got, nil)
    end)

    test("ambient cancel wakes a sleeping matcher", function()
      local h = handle.new()
      local elapsed_ms
      async.scope(function(n)
        n.spawn(function()
          local db = factory(lib.noop, function()
            async.sleep(80)
            coroutine.yield "never"
          end)
          local start = vim.uv.hrtime()
          local _ = db.search {}()
          elapsed_ms = (vim.uv.hrtime() - start) / 1e6
          db.close()
        end)
        async.sleep(5)
        h.cancel()
      end, h)
      assert(elapsed_ms and elapsed_ms < 40, ("expected fast wake, got %s ms"):format(tostring(elapsed_ms)))
    end)
  end)
end

cancel_tests("regular", producer.new)
cancel_tests("threaded", threaded.new)
