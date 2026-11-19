local T = require "coq.lib.test"
local async = require "coq.lib.async"

T.describe({ "wait" }, function(test)
  test({ "returns fn's result when fn finishes first" }, function()
    local result = async.wait(200 * T.SLOW, function()
      async.sleep(5 * T.SLOW)
      return "labrador"
    end)
    T.eq(result, "labrador")
  end)

  test({ "returns nil when timeout fires first" }, function()
    local result = async.wait(5 * T.SLOW, function()
      async.sleep(200 * T.SLOW)
      return "labrador"
    end)
    T.eq(result, nil)
  end)

  test({ "does not wait beyond fn's completion when fn wins" }, function()
    local checkpoints = {}
    async.scope(function(n)
      n.spawn(function()
        async.sleep(100 * T.SLOW)
        table.insert(checkpoints, "sentinel")
      end)
      async.wait(200 * T.SLOW, function()
        async.sleep(5 * T.SLOW)
        return "spot"
      end)
      table.insert(checkpoints, "wait")
      n.cancel()
    end)
    T.eq(checkpoints, { "wait" })
  end)

  test({ "does not wait beyond timeout when fn loses" }, function()
    local checkpoints = {}
    async.scope(function(n)
      n.spawn(function()
        async.sleep(200 * T.SLOW)
        table.insert(checkpoints, "sentinel")
      end)
      async.wait(10 * T.SLOW, function()
        async.sleep(500 * T.SLOW)
      end)
      table.insert(checkpoints, "wait")
      n.cancel()
    end)
    T.eq(checkpoints, { "wait" })
  end)

  test({ "forwards fn's nil return when fn finishes first" }, function()
    local result = async.wait(200 * T.SLOW, function()
      async.sleep(5 * T.SLOW)
      return nil
    end)
    T.eq(result, nil)
  end)
end)
