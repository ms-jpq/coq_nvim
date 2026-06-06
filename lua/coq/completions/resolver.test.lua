local T = require "coq.lib.test"
local async = require "coq.lib.async"
local cancel = require "coq.lib.async.cancel"
local resolver_m = require "coq.completions.resolver"

---@type ctx.base
local CTX = { win = 0, buf = 0, pos = { 0, 0 }, line = "", changedtick = 0, filetype = "" }

---@return completions.Item
local lsp_item = function(tag)
  return { word = tag, meta = { uid = tag, source = "LSP", filter = tag, fuzzy = 0, lsp = { tag = tag } } } --[[@as completions.Item]]
end

T.describe("resolver", function(test)
  test("caches resolved results by uid", function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, function(_, item)
        calls = calls + 1
        return item.meta.lsp
      end)
      local item = lsp_item "fido"
      local a = r.resolve(CTX, item)
      local b = r.resolve(CTX, item)
      T.eq(a, item.meta.lsp)
      T.eq(b, item.meta.lsp)
    end)
    T.eq(calls, 1)
  end)

  -- nvim deep-copies item.user_data through VimL, so highlight and commit see
  -- DISTINCT tables with identical content. The cache must key on content.
  test("shares cache across distinct tables of equal content", function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, function(_, item)
        calls = calls + 1
        return item.meta.lsp
      end)
      local highlight_copy = lsp_item "fido"
      local commit_copy = lsp_item "fido"
      assert(highlight_copy ~= commit_copy, "fixture must use distinct tables")
      r.resolve(CTX, highlight_copy)
      r.resolve(CTX, commit_copy)
    end)
    T.eq(calls, 1)
  end)

  test("dedups concurrent in-flight requests", function()
    local calls = 0
    local got = {}
    async.scope(function(n)
      local gate = async.future()
      local started = async.future()
      local r = resolver_m.new(n, function(_, item)
        calls = calls + 1
        started.resolve()
        gate.await()
        return item.meta.lsp
      end)
      local item = lsp_item "spot"

      n.spawn(function()
        got.a = r.resolve(CTX, item)
      end)
      n.spawn(function()
        got.b = r.resolve(CTX, item)
      end)

      started.await()
      gate.resolve()
    end)

    T.eq(calls, 1)
    assert(got.a ~= nil and got.a == got.b, "both awaiters should share the resolved value")
  end)

  test("reset clears state and re-fetches", function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, function(_, item)
        calls = calls + 1
        return item.meta.lsp
      end)
      local item = lsp_item "lil"
      r.resolve(CTX, item)
      r.reset()
      r.resolve(CTX, item)
    end)
    T.eq(calls, 2)
  end)

  -- reset() starts a new cycle with its own cache. A previous cycle's in-flight
  -- fetch that fails/cancels AFTER the reset must clean up against its OWN
  -- (discarded) cache, never the new cycle's live one.
  test("a stale cycle's failed fetch does not evict the new cycle's entry", function()
    local calls = 0
    async.scope(function(n)
      local started = async.future()
      local release = async.future()
      local hold = true
      local r = resolver_m.new(n, function(_, item)
        calls = calls + 1
        if hold then
          hold = false
          started.resolve()
          release.await()
          error(cancel.new(), 0) -- cycle-1 fetch cancels in-flight
        end
        return item.meta.lsp
      end)
      local item = lsp_item "fido"

      -- cycle 1: kick off a fetch and leave it parked in-flight
      n.spawn(function()
        r.resolve(CTX, item)
      end)
      started.await()

      -- new cycle; its fetch succeeds and caches under the same uid
      r.reset()
      r.resolve(CTX, item)

      -- now let cycle-1's fetch unwind; its cleanup must not touch cycle 2
      release.resolve()

      -- cycle 2's entry survives → no third fetch
      r.resolve(CTX, item)
    end)
    T.eq(calls, 2)
  end)

  test("caches a nil result without re-fetching", function()
    local calls = 0
    async.scope(function(n)
      local r = resolver_m.new(n, function()
        calls = calls + 1
        return nil
      end)
      local item = { word = "rex", meta = { uid = "rex", source = "BF", filter = "rex", fuzzy = 0 } } --[[@as completions.Item]]
      T.eq(r.resolve(CTX, item), nil)
      T.eq(r.resolve(CTX, item), nil)
    end)
    T.eq(calls, 1)
  end)
end)
