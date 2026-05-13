local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe("nursery", function(test)
  test("join returns immediately when no tasks spawned", function()
    async.run(async.ROOT, function()
      local n = async.nursery()
      n.join()
    end)
  end)

  test("join awaits all spawned children", function()
    async.run(async.ROOT, function()
      local n = async.nursery()
      local count = 0
      n.spawn(function()
        async.sleep(10)
        count = count + 1
      end)
      n.spawn(function()
        async.sleep(20)
        count = count + 1
      end)

      n.join()
      T.eq(count, 2)
    end)
  end)

  test("join returns immediately for synchronous children", function()
    async.run(async.ROOT, function()
      local n = async.nursery()
      local count = 0
      n.spawn(function()
        count = count + 1
      end)
      n.spawn(function()
        count = count + 1
      end)

      n.join()
      T.eq(count, 2)
    end)
  end)

  test("join wakes when ambient cancelled mid-join", function()
    local outer = async.handle()
    local joined = false
    async.run(outer, function()
      local n = async.nursery()
      n.spawn(function()
        async.sleep(200)
      end)
      n.join()
      joined = true
    end)

    async.sleep(5)
    outer.cancel()
    async.sleep(20)

    T.eq(joined, true)
  end)

  test("join re-raises first child error", function()
    async.run(async.ROOT, function()
      local n = async.nursery()
      n.spawn(function()
        error "child went missing"
      end)
      local ok, err = pcall(n.join)
      T.eq(ok, false)
      assert(err:find "child went missing")
    end)
  end)
end)

T.describe("scope", function(test)
  test("joins spawned tasks before returning", function()
    async.run(async.ROOT, function()
      local count = 0
      async.scope(function(n)
        n.spawn(function()
          async.sleep(5)
          count = count + 1
        end)
        n.spawn(function()
          async.sleep(10)
          count = count + 1
        end)
      end)
      T.eq(count, 2)
    end)
  end)

  test("cancels and re-raises on body error", function()
    async.run(async.ROOT, function()
      local cancelled = false
      local ok, err = pcall(function()
        async.scope(function(n)
          n.spawn(function()
            async.current().watch(function()
              cancelled = true
            end)
            async.sleep(100)
          end)
          error "body went sideways"
        end)
      end)
      T.eq(ok, false)
      T.eq(cancelled, true)
      assert(err:find "body went sideways")
    end)
  end)

  test("cancels and re-raises on child error", function()
    async.run(async.ROOT, function()
      local sibling_cancelled = false
      local ok, err = pcall(function()
        async.scope(function(n)
          n.spawn(function()
            async.current().watch(function()
              sibling_cancelled = true
            end)
            async.sleep(100)
          end)
          n.spawn(function()
            async.sleep(5)
            error "child went missing"
          end)
        end)
      end)
      T.eq(ok, false)
      T.eq(sibling_cancelled, true)
      assert(err:find "child went missing")
    end)
  end)
end)
