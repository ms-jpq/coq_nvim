local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.cancel"

local delayed = function(value, delay)
  local sent = false
  return function()
    if sent then
      return nil
    end
    async.sleep(delay)
    if async.current_token().cancelled then
      return nil
    end
    sent = true
    return value
  end
end

T.describe("merge", function(test)
  test("of one iter yields values until exhausted", function()
    local i = 0
    local iter = function()
      i = i + 1
      if i > 3 then
        return nil
      end
      async.sleep(2)
      return i * 10
    end

    local out = {}
    for v in async.merge { iter } do
      table.insert(out, v)
    end
    T.eq(out, { 10, 20, 30 })
  end)

  test("returns each iter's value in completion order", function()
    local out = {}
    for v in
      async.merge {
        delayed("a", 5),
        delayed("c", 15),
        delayed("b", 10),
      }
    do
      table.insert(out, v)
    end
    T.eq(out, { "a", "b", "c" })
  end)

  test("returns nil when ambient token cancelled mid-merge", function()
    local token = cancel.token()
    local got
    async.run(token, function()
      local iter = function()
        async.sleep(100)
        return "never"
      end
      got = async.merge { iter }()
    end)

    token.cancel()
    T.eq(got, nil)
  end)

  test("explicit cancel token short-circuits the merge", function()
    local scope = cancel.token()
    local got
    async.run(cancel.ROOT, function()
      local iter = function()
        async.sleep(100)
        return "never"
      end
      got = async.merge { cancel = scope, iter }()
    end)

    scope.cancel()
    T.eq(got, nil)
  end)
end)
