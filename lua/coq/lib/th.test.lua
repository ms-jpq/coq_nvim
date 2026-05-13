local T = require "coq.lib.test"
local th = require "coq.lib.th"

T.describe("th", function(test)
  test("returns string result", function()
    local result = th.run(function(name)
      return name .. ":woof"
    end, { "rex" })
    T.eq(result, "rex:woof")
  end)

  test("returns number result", function()
    local result = th.run(function(a, b)
      return a + b
    end, { 7, 3 })
    T.eq(result, 10)
  end)

  test("returns table result", function()
    local result = th.run(function()
      return { name = "rex", age = 7, sounds = { "woof", "growl" } }
    end, {})
    T.eq(result, { name = "rex", age = 7, sounds = { "woof", "growl" } })
  end)

  test("worker has no vim.fn", function()
    local has_fn = th.run(function()
      return vim.fn ~= nil
    end, {})
    T.eq(has_fn, false)
  end)

  test("worker errors propagate", function()
    local ok, err = pcall(th.run, function()
      error "rex went missing"
    end, {})
    T.eq(ok, false)
    assert(err:find "rex went missing", "expected error message, got: " .. tostring(err))
  end)
end)
