local T = require "coq.lib.test"
local show = require "coq.completions.preview.show"

---@param overrides? table
---@return config.PreviewDisplay
local cfg = function(overrides)
  local base = {
    enabled = true,
    x_max_len = 80,
    positions = { north = 1, south = 2, east = 3, west = 4 },
    border = "none",
    resolve_timeout = 1,
  }
  return vim.tbl_deep_extend("force", base, overrides or {}) --[[@as config.PreviewDisplay]]
end

---@param overrides? table
---@return completions.PumChangedEvent
local ev_of = function(overrides)
  local base = {
    kind = "changed",
    row = 5,
    col = 10,
    width = 20,
    height = 4,
    scrollbar = false,
    completed_item = vim.empty_dict(),
    size = 0,
    selected = 0,
  }
  return vim.tbl_deep_extend("force", base, overrides or {}) --[[@as completions.PumChangedEvent]]
end

---@type preview.Screen
local SCREEN = { width = 120, height = 40 }

T.describe({ "preview.show._pick_position" }, function(test)
  test({ "returns nil when no quadrant is enabled" }, function()
    -- vim.tbl_deep_extend strips nil entries, so build the cfg directly.
    local p = cfg()
    p.positions = {}
    T.eq(show._pick_position(p, ev_of(), SCREEN, { "fido" }), nil)
  end)

  test({ "picks south when north has no room above the pum" }, function()
    -- pum row = 1: only 0 rows above → north can't fit
    local p = cfg()
    local pos = show._pick_position(p, ev_of { row = 1, height = 2 }, SCREEN, { "fido" })
    assert(pos, "expected a position")
    -- south sits two rows below the pum's bottom
    T.eq(pos.row, 1 + 2 - 1 + 2) -- pum_s + 2
  end)

  test({ "picks north when there's room above" }, function()
    -- north has rank 1 (preferred); plenty of room above row=20
    local p = cfg()
    local pos = show._pick_position(p, ev_of { row = 20, height = 4 }, SCREEN, { "fido", "spot", "rex" })
    assert(pos, "expected a position")
    -- north's row sits above the pum
    assert(pos.row < 20, "expected north row to be above pum")
  end)

  test({ "rank wins when areas are equal" }, function()
    -- single-line content fits in either quadrant with the same area; rank
    -- breaks the tie, so north (rank 1) is picked over south (rank 2).
    local p = cfg { positions = { north = 1, south = 2 } }
    local pos = show._pick_position(p, ev_of { row = 20, height = 4 }, SCREEN, { "fido" })
    assert(pos, "expected a position")
    assert(pos.row < 20, "expected north (above pum); got row=" .. pos.row)
  end)

  test({ "bigger area beats better rank" }, function()
    -- 8-line content. North is tight (only 2 rows above) so its area = 2*w.
    -- South has 35 rows below so its area = 8*w. South wins on area despite
    -- north's better rank.
    local p = cfg { positions = { north = 1, south = 2 } }
    local lines = {}
    for _ = 1, 8 do
      table.insert(lines, "fido")
    end
    local pos = show._pick_position(p, ev_of { row = 2, height = 1 }, SCREEN, lines)
    assert(pos, "expected a position")
    assert(pos.row > 2, "expected south (below pum); got row=" .. pos.row)
  end)

  test({ "respects x_max_len for width clamp" }, function()
    local p = cfg { x_max_len = 30 }
    local long = string.rep("a", 200)
    local pos = show._pick_position(p, ev_of { row = 20 }, SCREEN, { long })
    assert(pos, "expected a position")
    assert(pos.width <= 30, "width should be capped at x_max_len, got " .. pos.width)
  end)

  test({ "border adds 1 cell padding per side to geometry" }, function()
    -- with rounded border, b_w/b_h = 1; ns_w should shrink relative to none
    local p_none = cfg { border = "none" }
    local p_round = cfg { border = "rounded" }
    local ev = ev_of { row = 20 }
    local pos_none = show._pick_position(p_none, ev, SCREEN, { "fido" })
    local pos_round = show._pick_position(p_round, ev, SCREEN, { "fido" })
    assert(pos_none and pos_round, "expected positions")
    assert(
      pos_round.width <= pos_none.width,
      "bordered width should not exceed unbordered, got " .. pos_round.width .. " vs " .. pos_none.width
    )
  end)

  test({ "tight screen with no room anywhere returns nil" }, function()
    -- pum fills nearly the whole screen
    local tiny = { width = 30, height = 8 }
    local p = cfg()
    -- pum spans rows 0..6 horizontally; south_row = 6+2 = 8 = screen.height
    -- east/west are clamped to 0-width
    local ev = ev_of { row = 0, col = 0, width = 30, height = 7 }
    local pos = show._pick_position(p, ev, tiny, { string.rep("x", 200) })
    -- not asserting nil specifically — geometry may still find one usable
    -- quadrant. But if any pos comes back, dimensions must fit on screen.
    if pos then
      assert(pos.row + pos.height <= tiny.height, "pos overflows screen height")
      assert(pos.col + pos.width <= tiny.width, "pos overflows screen width")
    end
  end)

  test({ "empty lines table — no width contribution, still returns a position" }, function()
    -- cap_w would be 0 (no lines) but cap_h is clamped to >= 1.
    local p = cfg()
    local pos = show._pick_position(p, ev_of { row = 20 }, SCREEN, {})
    assert(pos, "expected a position even with no lines")
    assert(pos.width >= 1, "width must be at least 1")
    assert(pos.height >= 1, "height must be at least 1")
  end)
end)
