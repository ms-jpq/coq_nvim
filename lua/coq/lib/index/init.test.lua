local T = require "coq.lib.test"
local async = require "coq.lib.async"
local search = require "coq.lib.index"

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
      return next(items) == nil
    end,
    search = function(_)
      local snapshot = items
      return async.wrap(function()
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

  test("prune reports emptiness and drops drained children", function()
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
    idx.insert { word = "spot", filetype = "python", buf = 2 }

    -- buf 1 drains the lua child (dropped); python survives → not empty
    T.eq(idx.prune { buf = 1 }, false)
    T.eq(collect(idx.search { filetype = "lua" }), {})
    -- buf 2 drains the last child → index reports empty
    T.eq(idx.prune { buf = 2 }, true)
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
