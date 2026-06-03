local T = require "coq.lib.test"
local fuzzy = require "coq.lib.index.fuzzy"

---@param cutoff number
local spec_with = function(cutoff)
  return {
    insert_key = function(item)
      return item.word
    end,
    query_key = function(ctx)
      return ctx.token
    end,
    cutoff = cutoff,
  }
end

---@param iter fun(): index.Hit<any>?
local collect = function(iter)
  local out = {}
  for hit in iter do
    table.insert(out, hit.item.word)
  end
  table.sort(out)
  return out
end

-- "poodle" shares no ordered subsequence with "lab" -> match.score == 0.
T.describe("fuzzy.cutoff", function(test)
  test("a zero cutoff yields every item, including non-matches", function()
    local f = fuzzy.new(spec_with(0))
    f.insert { word = "labrador" }
    f.insert { word = "poodle" }

    T.eq(collect(f.search { token = "lab" }), { "labrador", "poodle" })
  end)

  test("a positive cutoff drops items that do not match the token", function()
    local f = fuzzy.new(spec_with(0.6))
    f.insert { word = "labrador" }
    f.insert { word = "poodle" }

    -- poodle scores 0 against "lab" and falls below the cutoff; labrador matches.
    T.eq(collect(f.search { token = "lab" }), { "labrador" })
  end)

  test("an empty token bypasses the cutoff (everything scores 0)", function()
    local f = fuzzy.new(spec_with(0.6))
    f.insert { word = "labrador" }
    f.insert { word = "poodle" }

    -- no keyword to match against -> the cutoff must not blank the list.
    T.eq(collect(f.search { token = "" }), { "labrador", "poodle" })
  end)
end)
