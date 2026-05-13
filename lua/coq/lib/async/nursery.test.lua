local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"

T.describe("nursery", function(test)
  test("join returns immediately when no tasks spawned", function()
    local n = async.nursery()
    n.join()
  end)

  test("join awaits all spawned children", function()
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

  test("join returns immediately for synchronous children", function()
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

  test("join wakes when ambient cancelled mid-join", function()
    local outer = handle.new()
    local joined = false
    async.scope(outer, function(n)
      n.spawn(function()
        local inner = async.nursery()
        inner.spawn(function()
          async.sleep(200)
        end)
        inner.join()
        joined = true
      end)
      async.sleep(5)
      outer.cancel()
    end)

    T.eq(joined, true)
  end)

  test("join re-raises first child error", function()
    local n = async.nursery()
    n.spawn(function()
      error "child went missing"
    end)
    local ok, err = pcall(n.join)

    T.eq(ok, false)
    assert(err:find "child went missing")
  end)

  test("spawn after close raises", function()
    local n = async.nursery()
    n.close()

    local ok, err = pcall(n.spawn, function() end)
    T.eq(ok, false)
    assert(tostring(err):find "nursery is closed")
  end)

  test("join raises error group when multiple children error", function()
    local n = async.nursery()
    n.spawn(function()
      error "first"
    end)
    n.spawn(function()
      async.sleep(50)
      error "second"
    end)

    local ok, err = pcall(n.join)
    T.eq(ok, false)
    T.eq(#err.errs, 2)
    assert(tostring(err.errs[1]):find "first")
    assert(tostring(err.errs[2]):find "second")
  end)
end)

T.describe("scope", function(test)
  test("joins spawned tasks before returning", function()
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

  test("cancels and re-raises on body error", function()
    local cancelled = false
    local ok, err = pcall(function()
      async.scope(function(n)
        n.spawn(function()
          async.current().on_cancel(function()
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

  test("cancels and re-raises on child error", function()
    local sibling_cancelled = false
    local ok, err = pcall(function()
      async.scope(function(n)
        n.spawn(function()
          async.current().on_cancel(function()
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
