local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("join", function(test)
  test("returns immediately when no tasks registered", function()
    async.run(async.ROOT, function()
      local h = async.handle()
      async.join(h)
    end)
  end)

  test("awaits all spawned children", function()
    async.run(async.ROOT, function()
      local h = async.handle()
      local count = 0
      async.run(h, function()
        async.sleep(10)
        count = count + 1
      end)
      async.run(h, function()
        async.sleep(20)
        count = count + 1
      end)

      async.join(h)
      T.eq(count, 2)
    end)
  end)

  test("returns immediately for synchronous children", function()
    async.run(async.ROOT, function()
      local h = async.handle()
      local count = 0
      async.run(h, function()
        count = count + 1
      end)
      async.run(h, function()
        count = count + 1
      end)

      async.join(h)
      T.eq(count, 2)
    end)
  end)

  test("wakes when ambient cancelled during join", function()
    local h = async.handle()
    local joined = false
    async.run(h, function()
      local inner = async.handle()
      async.run(inner, function()
        async.sleep(200)
      end)
      async.join(inner)
      joined = true
    end)

    async.sleep(5)
    h.cancel()
    async.sleep(20)

    T.eq(joined, true)
  end)
end)
