---@diagnostic disable: missing-fields
local T = require "coq.lib.test"
local async = require "coq.lib.async"
local handle = require "coq.lib.async.handle"
local search = require "coq.lib.index"

T.describe("index.iter", function(test)
  test("yields values from the body in order", function()
    local h = handle.new()
    local iter = search.iter(h, function()
      coroutine.yield "lil"
      coroutine.yield "spot"
      coroutine.yield "fido"
    end)

    T.eq(iter(), "lil")
    T.eq(iter(), "spot")
    T.eq(iter(), "fido")
    T.eq(iter(), nil)
  end)

  test("exhaustion cancels the handle", function()
    local h = handle.new()
    local iter = search.iter(h, function()
      coroutine.yield "lil"
    end)
    iter()
    iter()

    T.eq(h.cancelled, true)
  end)

  test("close cancels the handle and stops further pulls", function()
    local pulls = 0
    local h = handle.new()
    local iter = search.iter(h, function()
      while true do
        pulls = pulls + 1
        coroutine.yield "row"
      end
    end)

    T.eq(iter(), "row")
    iter.close()
    T.eq(h.cancelled, true)
    T.eq(iter(), nil)
    T.eq(pulls, 1)
  end)

  test("external handle cancel closes the iter", function()
    local h = handle.new()
    local iter = search.iter(h, function()
      while true do
        coroutine.yield "row"
      end
    end)
    T.eq(iter(), "row")
    h.cancel()

    T.eq(iter(), nil)
  end)

  test("body error propagates and closes the iter", function()
    local h = handle.new()
    local iter = search.iter(h, function()
      coroutine.yield "lil"
      error "boom"
    end)
    T.eq(iter(), "lil")

    local ok, err = pcall(iter)
    T.eq(ok, false)
    assert(err and tostring(err):find "boom", "expected 'boom', got: " .. tostring(err))
    T.eq(h.cancelled, true)
  end)

  test("body can await between yields", function()
    local out = {}
    async.scope(function(n)
      n.spawn(function()
        local h = handle.new()
        local iter = search.iter(h, function()
          coroutine.yield "lil"
          async.sleep(2 * T.SLOW)
          coroutine.yield "spot"
        end)
        for v in iter do
          table.insert(out, v)
        end
      end)
    end)

    T.eq(out, { "lil", "spot" })
  end)

  test("cancellation while body awaits drops the in-flight value", function()
    local first, after
    async.scope(function(n)
      local h = handle.new()
      local iter = search.iter(h, function()
        coroutine.yield "lil"
        async.sleep(100 * T.SLOW)
        coroutine.yield "never"
      end)
      n.spawn(function()
        first = iter()
        after = iter()
      end)
      async.sleep(5 * T.SLOW)
      h.cancel()
    end)

    T.eq(first, "lil")
    T.eq(after, nil)
  end)

  test("close is idempotent", function()
    local h = handle.new()
    local iter = search.iter(h, function()
      coroutine.yield "lil"
    end)
    iter.close()
    iter.close() -- no error
  end)
end)

---@return index.Searcher<table>
local leaf = function()
  local items = {}
  return {
    close = function()
      items = {}
    end,
    insert = function(item)
      table.insert(items, item)
    end,
    prune = function(ctx)
      if ctx.buf ~= nil then
        items = vim
          .iter(items)
          :filter(function(item)
            return item.buf ~= ctx.buf
          end)
          :totable()
      else
        items = {}
      end
    end,
    search = function(_)
      local snapshot = items
      local h = handle.new()
      return search.iter(h, function()
        for _, item in ipairs(snapshot) do
          coroutine.yield(item)
        end
      end)
    end,
  }
end

local collect = function(iter)
  local out = {}
  for item in iter do
    table.insert(out, item.word)
  end
  table.sort(out)
  return out
end

T.describe("index.indexed", function(test)
  test("search routes by query_key to a single child", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }
    idx.insert { word = "lil", filetype = "lua" }
    idx.insert { word = "spot", filetype = "python" }
    idx.insert { word = "fido", filetype = "lua" }

    T.eq(collect(idx.search { filetype = "lua" }), { "fido", "lil" })
    T.eq(collect(idx.search { filetype = "python" }), { "spot" })
  end)

  test("query_key returning nil fans out across all children", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }
    idx.insert { word = "lil", filetype = "lua" }
    idx.insert { word = "spot", filetype = "python" }
    idx.insert { word = "fido", filetype = "rust" }

    T.eq(collect(idx.search {}), { "fido", "lil", "spot" })
  end)

  test("search with a key that has no child yields nothing", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }
    idx.insert { word = "lil", filetype = "lua" }

    T.eq(collect(idx.search { filetype = "rust" }), {})
  end)

  test("insert lazily creates child buckets", function()
    local created = 0
    local counted_leaf = function()
      created = created + 1
      return leaf()
    end
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = counted_leaf,
    }
    idx.insert { word = "lil", filetype = "lua" }
    idx.insert { word = "fido", filetype = "lua" }
    idx.insert { word = "spot", filetype = "python" }

    T.eq(created, 2)
  end)

  test("prune with non-nil query_key only touches the matching child", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }
    idx.insert { word = "lil", filetype = "lua", buf = 1 }
    idx.insert { word = "spot", filetype = "python", buf = 1 }

    idx.prune { filetype = "lua", buf = 1 }

    T.eq(collect(idx.search { filetype = "lua" }), {})
    T.eq(collect(idx.search { filetype = "python" }), { "spot" })
  end)

  test("prune with nil query_key fans out across all children", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }
    idx.insert { word = "lil", filetype = "lua", buf = 1 }
    idx.insert { word = "spot", filetype = "python", buf = 1 }
    idx.insert { word = "fido", filetype = "lua", buf = 2 }

    idx.prune { buf = 1 }

    T.eq(collect(idx.search { filetype = "lua" }), { "fido" })
    T.eq(collect(idx.search { filetype = "python" }), {})
  end)

  test("two layers route filetype then prefix", function()
    local inner_layer = function()
      return search.indexed {
        insert_key = function(item)
          return string.sub(item.word, 1, 2)
        end,
        query_key = function(ctx)
          return ctx.prefix and string.sub(ctx.prefix, 1, 2) or nil
        end,
        child = leaf,
      }
    end
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = inner_layer,
    }
    idx.insert { word = "filter", filetype = "lua" }
    idx.insert { word = "field", filetype = "lua" }
    idx.insert { word = "spot", filetype = "lua" }
    idx.insert { word = "filter", filetype = "python" }

    T.eq(collect(idx.search { filetype = "lua", prefix = "fi" }), { "field", "filter" })
    T.eq(collect(idx.search { filetype = "lua" }), { "field", "filter", "spot" })
    T.eq(collect(idx.search { filetype = "python", prefix = "fi" }), { "filter" })
  end)

  test("empty index yields nothing", function()
    local idx = search.indexed {
      insert_key = function(item)
        return item.filetype
      end,
      query_key = function(ctx)
        return ctx.filetype
      end,
      child = leaf,
    }

    T.eq(collect(idx.search {}), {})
    T.eq(collect(idx.search { filetype = "lua" }), {})
  end)
end)

T.describe("index.empty", function(test)
  test("search yields nothing; insert/prune are no-ops", function()
    local got = {}
    for item in search.empty.search {} do
      table.insert(got, item)
    end
    T.eq(got, {})

    -- these should not error
    search.empty.insert { word = "lil" }
    search.empty.prune {}
  end)
end)
