local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"

T.describe("preemptible", function(test)
  test("forwards values from underlying iter", function()
    local i = 0
    local iter = async.preemptible(function()
      i = i + 1
      if i > 3 then
        return nil
      end
      return i * 10
    end)

    local out = {}
    while true do
      local v = iter()
      if v == nil then
        break
      end
      table.insert(out, v)
    end

    T.eq(out, { 10, 20, 30 })
  end)

  test("returns nil when underlying iter exhausts", function()
    local iter = async.preemptible(function()
      return nil
    end)

    T.eq(iter(), nil)
  end)

  test("forwards values across async yields", function()
    local i = 0
    local iter = async.preemptible(function()
      i = i + 1
      if i > 2 then
        return nil
      end
      async.sleep(2)
      return "fido" .. i
    end)

    T.eq(iter(), "fido1")
    T.eq(iter(), "fido2")
    T.eq(iter(), nil)
  end)

  test("returns nil when ambient cancelled mid-iter", function()
    local h = handle.new()
    local got
    async.scope(h, function(n)
      n.spawn(function()
        local iter = async.preemptible(function()
          async.sleep(100)
          return "never"
        end)
        got = iter()
      end)
      async.sleep(5)
      h.cancel()
    end)

    T.eq(got, nil)
  end)

  test("returns nil when ambient already cancelled before call", function()
    local h = handle.new()
    h.cancel()
    local got
    async.scope(h, function(n)
      n.spawn(function()
        local iter = async.preemptible(function()
          return "never"
        end)
        got = iter()
      end)
    end)

    T.eq(got, nil)
  end)

  test("propagates errors from underlying iter", function()
    local iter = async.preemptible(function()
      error "kibble crash"
    end)

    local ok, err = pcall(iter)

    T.eq(ok, false)
    assert(tostring(err):find "kibble crash")
  end)
end)
