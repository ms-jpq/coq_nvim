local T = require "coq.lib.test"
local async = require "coq.lib.async"
local config = require "coq.config"
local helpers = require "coq.lib.test_helpers"
local measure = require "coq.lib.index.rank.measure"
local producer = require "coq.lib.producers"
local rank = require "coq.lib.index.rank"
local util = require "coq.producers.util"

local SETTINGS = config.merged { weights = { prefix_matches = 2, edit_distance = 1.5, recency = 1, proximity = 0.5 } }

---@param word string
---@param overrides? table
---@return completions.Item
local item = function(word, overrides)
  return vim.tbl_deep_extend("force", {
    word = word,
    kind = "",
    meta = { uid = word, filter = { word }, source = "buffers", fuzzy = 0 },
  }, overrides or {})
end

---@param overrides? table
---@return ctx.full
local context = function(overrides)
  return helpers.ctx_of(vim.tbl_deep_extend("force", {
    iskeyword = "@,48-57,_",
    keyword_before = "dog",
  }, overrides or {}))
end

local words = function(items)
  return vim.tbl_map(function(entry)
    return entry.word
  end, items)
end

T.describe({ "rank" }, function(test)
  test({ "candidate character selects context text" }, function()
    local p = context { symbol_before = "->", line_before = "  " }
    local measured = measure.batch(SETTINGS, p, { item "dogs", item "->field", item "  dog", item "" })
    local prefixes = vim.tbl_map(function(entry)
      return entry.metrics[1].prefix_matches
    end, measured)
    T.eq(prefixes, { 3, 2, 2, 0 })
    local custom = measure.batch(
      SETTINGS,
      context { iskeyword = "@,48-57,_,-", keyword_before = "-d", symbol_before = "-" },
      { item "-dog" }
    )
    T.eq(custom[1].metrics[1].prefix_matches, 2)
  end)

  test({ "common measurement covers both full and partial batches" }, function()
    async.scope(function()
      local p = context()
      local sizes = {}
      local matcher = util.batched(function()
        for _ = 1, util.BATCH + 1 do
          coroutine.yield(item "dog")
        end
      end)
      ---@diagnostic disable-next-line: unused-vararg
      local pull = async.wrap(function(...)
        matcher(SETTINGS, p)
      end)
      local collector = rank.new(SETTINGS, { dog = 12 }, p)
      while true do
        local batch = pull(true)
        if batch == nil then
          break
        end
        table.insert(sizes, #batch)
        for _, candidate in ipairs(batch) do
          T.eq(candidate.metrics, { { prefix_matches = 3, edit_distance = 1, proximity = 0 } })
        end
        collector.add(batch)
      end
      T.eq(sizes, { util.BATCH, 1 })
      T.eq(collector.rank(1)[1].word, "dog")
    end)
  end)

  test({ "incremental collection matches whole-set ranking after intermediate reads" }, function()
    local p = context()
    local history = { dig = 20 }
    local items = { item "dot", item "dog", item "dig" }
    local original = vim.deepcopy(items)
    local measured = measure.batch(SETTINGS, p, items)
    local original_measured = vim.deepcopy(measured)
    T.eq(items, original)
    T.eq(measured[1].item == items[1], true)
    local collector = rank.new(SETTINGS, history, p)
    T.eq(collector.rank(3), {})
    collector.add { measured[1], measured[2] }
    T.eq(words(collector.rank(3)), { "dog", "dot" })
    collector.add { measured[3] }
    local expected = words(rank.rank(SETTINGS, history, p, items, 3))
    T.eq(words(collector.rank(3)), expected)
    T.eq(words(collector.rank(1)), { expected[1] })
    T.eq(words(collector.rank(3)), expected)
    T.eq(measured, original_measured)
    local without_history = rank.new(SETTINGS, {}, p)
    without_history.add(measured)
    T.eq(words(without_history.rank(3)), { "dog", "dot", "dig" })
    T.eq(expected, { "dig", "dog", "dot" })
  end)

  test({ "Unicode worker measurement uses bytewise lowercase without calling main" }, function()
    async.scope(function(_, defer)
      local p = context { keyword_before = "dög", locality = { ["DÖG"] = 2 } }
      local source = producer.threaded {
        source = "test",
        idle = function() end,
        matcher = function(settings, ctx)
          assert(vim.is_thread())
          require("coq.lib.worker").main = function()
            error "unexpected main-thread call"
          end
          require("coq.producers.util").batched(function()
            coroutine.yield {
              word = "DÖG",
              meta = { uid = "dog", filter = { "DÖG" }, source = "test", fuzzy = 0 },
            }
          end)(settings, ctx)
        end,
      }
      defer(source.close)
      local close, iter = source.search(SETTINGS, p)
      defer(close)
      local batch = assert(iter())
      T.eq(batch[1].metrics, { { prefix_matches = 1, edit_distance = 1 - 1 / 3, proximity = 2 } })
      T.eq(iter(), nil)
    end)
  end)

  test({ "ASCII worker measurement does not call the main thread" }, function()
    async.scope(function(_, defer)
      local source = producer.threaded {
        source = "test",
        idle = function() end,
        matcher = function(settings, ctx)
          assert(vim.is_thread())
          require("coq.lib.worker").main = function()
            error "unexpected main-thread call"
          end
          require("coq.producers.util").batched(function()
            coroutine.yield {
              word = "DOG",
              meta = { uid = "dog", filter = { "DOG" }, source = "test", fuzzy = 0 },
            }
          end)(settings, ctx)
        end,
      }
      defer(source.close)
      local close, iter = source.search(SETTINGS, context())
      defer(close)
      T.eq(assert(iter())[1].metrics, { { prefix_matches = 3, edit_distance = 1, proximity = 0 } })
      T.eq(iter(), nil)
    end)
  end)

  test({ "preselect precedes pinned candidates, which precede text scores" }, function()
    local items = {
      item "dog",
      item("rex", { meta = { always_on_top = true } }),
      item("spot", { meta = { lsp = { item = { preselect = true } } } }),
    }
    T.eq(words(rank.rank(SETTINGS, {}, context(), items, 3)), { "spot", "rex", "dog" })
  end)

  test({ "prefix and edit features use v1 candidate totals" }, function()
    local items = { item "dot", item "dog", item "dig" }
    T.eq(words(rank.rank(SETTINGS, {}, context(), items, 3)), { "dog", "dot", "dig" })
    T.eq(words(rank.rank(SETTINGS, { dig = 20 }, context(), items, 3)), { "dig", "dog", "dot" })
  end)

  test({ "weights can disable text features" }, function()
    local settings = config.merged { weights = { prefix_matches = 0, edit_distance = 0, proximity = 1, recency = 0 } }
    local p = context { locality = { rex = 2 } }
    T.eq(words(rank.rank(settings, {}, p, { item "dog", item "rex" }, 2)), { "rex", "dog" })
  end)

  test({ "source adjustment multiplies the combined score" }, function()
    local items = { item("dog", { meta = { source = "lsp" } }), item "dogs" }
    local settings = vim.tbl_deep_extend("force", SETTINGS, { clients = { lsp = { weight_adjust = -1 } } })
    T.eq(words(rank.rank(settings, {}, context(), items, 2)), { "dogs", "dog" })
  end)

  test({ "deduplication and display limits follow ranking" }, function()
    local items = { item "dot", item "dig", item "dog", item("dog", { meta = { always_on_top = true } }) }
    local out = rank.rank(SETTINGS, {}, context(), items, 2)
    T.eq(words(out), { "dog", "dot" })
    T.eq(out[1].meta.always_on_top, true)
  end)

  test({ "equal keys retain arrival order" }, function()
    local items = { item("dog", { meta = { source = "lsp" } }), item "dog" }
    T.eq(rank.rank(SETTINGS, {}, context(), items, 2)[1].meta.source, "lsp")
  end)

  test({ "measurement accepts different text for the same items" }, function()
    local items = { item "dog", item "rex" }
    T.eq(words(rank.rank(SETTINGS, {}, context(), items, 2)), { "dog", "rex" })
    T.eq(words(rank.rank(SETTINGS, {}, context { keyword_before = "rex" }, items, 2)), { "rex", "dog" })
  end)

  test({ "empty match text has zero text metrics" }, function()
    local measured = measure.batch(SETTINGS, context { keyword_before = "" }, { item "dog" })
    T.eq(measured[1].metrics, { { prefix_matches = 0, edit_distance = 0, proximity = 0 } })
  end)
end)
