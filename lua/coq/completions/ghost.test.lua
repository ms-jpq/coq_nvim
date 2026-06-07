local T = require "coq.lib.test"
local ghost = require "coq.completions.ghost"

local NS = vim.api.nvim_create_namespace "coq.ghost"

-- `bind` wires up the stateful API (M.show, M.clear, etc.) and registers the
-- decoration provider. Tests don't go through events / nursery, so we pass
-- nil for both; `bind` skips subscriptions in that case.
---@diagnostic disable-next-line: missing-fields
ghost.bind(nil, {
  display = {
    ghost_text = { enabled = true, highlight_group = "Comment", show_count = false, proactive = true },
  },
  keymap = {},
}, nil)

---@param lines string[]
---@param row integer  -- 1-indexed
---@param col integer  -- 0-indexed byte
---@return integer buf
---@return ctx.base ctx
local mk_ctx = function(lines, row, col)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  local line = lines[row] or ""
  ---@type ctx.base
  ---@diagnostic disable-next-line: missing-fields
  local ctx = {
    buf = buf,
    win = 0,
    pos = { row, col, col, col },
    changedtick = 0,
    line = line,
    filetype = "",
  }
  return buf, ctx
end

---@return config.GhostText
local cfg = function(overrides)
  local base = {
    enabled = true,
    highlight_group = "Comment",
    count_highlight_group = "NonText",
    show_count = false,
    proactive = true,
  }
  return vim.tbl_extend("force", base, overrides or {}) --[[@as config.GhostText]]
end

---@param word string
---@return completions.Item
local item_of = function(word)
  ---@diagnostic disable-next-line: missing-fields
  return {
    word = word,
    meta = { uid = "x", source = "buffers", filter = word, fuzzy = 0 },
  } --[[@as completions.Item]]
end

-- The production renderer is a decoration provider — its extmarks are
-- ephemeral and only emitted mid-redraw. Tests read the opts table directly.
-- nvim normalizes some keys (eol + virt_text_win_col → "win_col"), so for
-- tests that care about the normalized form we round-trip through a
-- persistent extmark via mark_details.
---@diagnostic disable-next-line: unused-vararg
local mark_text = function(...)
  local opts = ghost._extmark_opts()
  return opts and opts.virt_text and opts.virt_text[1]
end

local mark_details = function(buf)
  local opts = ghost._extmark_opts()
  if not opts then
    return nil
  end
  opts.ephemeral = nil
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, opts)
  local marks = vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
  return marks[1] and marks[1][4]
end

T.describe({ "ghost.show typed-prefix suppression" }, function(test)
  test({ "renders the untyped tail only" }, function()
    local buf, ctx = mk_ctx({ "./ft" }, 1, 4)
    ghost.show(cfg(), ctx, item_of "ftplugin", 1, 1)
    local entry = mark_text(buf)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "plugin")
  end)

  test({ "nothing to render when typed matches the whole word" }, function()
    local buf, ctx = mk_ctx({ "ftplugin" }, 1, 8)
    ghost.show(cfg(), ctx, item_of "ftplugin", 1, 1)
    T.eq(mark_text(buf), nil)
  end)
end)

T.describe({ "ghost.show common-suffix removal" }, function(test)
  test({ "trims trailing chars already in the buffer" }, function()
    -- cursor between paren chars: user typed "fido(", cursor before ")".
    -- item word "fido()" — the trailing `)` is already in the buffer.
    local buf, ctx = mk_ctx({ "fido()" }, 1, 5)
    ghost.show(cfg(), ctx, item_of "fido()", 1, 1)
    -- typed_overlap("fido(", "fido()") = 5 → tail = ")"
    -- strip_common_suffix(after=")", suggestion=")") = ""
    T.eq(mark_text(buf), nil)
  end)
end)

T.describe({ "ghost.show range-driven overlay" }, function(test)
  ---@param newText string
  ---@param s integer
  ---@param e integer
  ---@return completions.Item
  local item_with_range = function(newText, s, e)
    ---@diagnostic disable-next-line: missing-fields
    return {
      word = newText,
      meta = {
        uid = "x",
        source = "LSP",
        filter = newText,
        fuzzy = 0,
        lsp = {
          position_encoding = "utf-8",
          ---@diagnostic disable-next-line: missing-fields
          item = {
            textEdit = {
              newText = newText,
              range = {
                start = { line = 0, character = s },
                ["end"] = { line = 0, character = e },
              },
            },
          },
        },
      },
    } --[[@as completions.Item]]
  end

  test({ "non-empty range → overlay (mirrors vim.lsp.inline_completion)" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(cfg(), ctx, item_with_range("fido", 0, 4), 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
  end)

  test({ "empty range → inline (degenerate range = pure insertion)" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(cfg(), ctx, item_with_range("do", 2, 2), 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "inline")
  end)

  test({ "no textEdit → inline (plain word item)" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(cfg(), ctx, item_of "fido", 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "inline")
  end)

  test({ "control chars trump range — eol still wins" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(cfg(), ctx, item_with_range("\tbody", 0, 5), 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "win_col") -- nvim normalizes eol+virt_text_win_col → win_col
  end)
end)

T.describe({ "ghost.show multi-line range" }, function(test)
  ---@param newText string
  ---@param s_line integer
  ---@param s_char integer
  ---@param e_line integer
  ---@param e_char integer
  ---@return completions.Item
  local item_ml_range = function(newText, s_line, s_char, e_line, e_char)
    ---@diagnostic disable-next-line: missing-fields
    return {
      word = newText,
      meta = {
        uid = "x",
        source = "LSP",
        filter = newText,
        fuzzy = 0,
        lsp = {
          position_encoding = "utf-8",
          ---@diagnostic disable-next-line: missing-fields
          item = {
            textEdit = {
              newText = newText,
              range = {
                start = { line = s_line, character = s_char },
                ["end"] = { line = e_line, character = e_char },
              },
            },
          },
        },
      },
    } --[[@as completions.Item]]
  end

  test({ "range N rows × newText K lines: emits min(N,K) per-row overlays" }, function()
    -- Range spans 3 rows, newText has 3 lines → 3 overlay extmarks
    -- (anchor at cursor col, others at col 0).
    local _, ctx = mk_ctx({ "dog", "good", "fido" }, 1, 0)
    ghost.show(cfg(), ctx, item_ml_range("puppy\nclever\nfido", 0, 0, 2, 4), 1, 1)
    local marks = ghost._extmarks()
    T.eq(#marks, 3)
    T.eq(marks[1].opts.virt_text[1][1], "puppy")
    T.eq(marks[1].opts.virt_text_pos, "overlay")
    T.eq(marks[1].col_at_cursor, true)
    T.eq(marks[2].opts.virt_text[1][1], "clever")
    T.eq(marks[2].opts.virt_text_pos, "overlay")
    T.eq(marks[2].col_at_cursor, false)
    T.eq(marks[2].row_offset, 1)
    T.eq(marks[3].opts.virt_text[1][1], "fido")
    T.eq(marks[3].row_offset, 2)
    -- No surplus virt_lines on the last mark.
    T.eq(marks[3].opts.virt_lines, nil)
  end)

  test({ "newText has more lines than range: surplus goes into virt_lines" }, function()
    -- 2-row range, 4-line newText → 2 overlays, 2 surplus → virt_lines on mark 2
    local _, ctx = mk_ctx({ "a", "b" }, 1, 0)
    ghost.show(cfg(), ctx, item_ml_range("L1\nL2\nL3\nL4", 0, 0, 1, 1), 1, 1)
    local marks = ghost._extmarks()
    T.eq(#marks, 2)
    T.eq(marks[1].opts.virt_text[1][1], "L1")
    T.eq(marks[2].opts.virt_text[1][1], "L2")
    assert(marks[2].opts.virt_lines, "expected virt_lines on last mark")
    T.eq(marks[2].opts.virt_lines[1][1][1], "L3")
    T.eq(marks[2].opts.virt_lines[2][1][1], "L4")
  end)

  test({ "range has more rows than newText: only emit row_overlays for newText lines" }, function()
    -- 3-row range, 1-line newText → 1 mark (anchor), buffer rows 2,3 leak (limitation)
    local _, ctx = mk_ctx({ "a", "b", "c" }, 1, 0)
    ghost.show(cfg(), ctx, item_ml_range("once", 0, 0, 2, 1), 1, 1)
    local marks = ghost._extmarks()
    T.eq(#marks, 1)
    T.eq(marks[1].opts.virt_text[1][1], "once")
  end)

  test({ "single-line range, multi-line newText: anchor + virt_lines (no extra overlays)" }, function()
    -- 1-row range stays as single overlay anchor; surplus lines as virt_lines.
    local _, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(cfg(), ctx, item_ml_range("fido\nbark", 0, 0, 0, 2), 1, 1)
    local marks = ghost._extmarks()
    T.eq(#marks, 1)
    T.eq(marks[1].opts.virt_text[1][1], "do")  -- "fi" prefix consumed
    assert(marks[1].opts.virt_lines, "expected virt_lines")
    T.eq(marks[1].opts.virt_lines[1][1][1], "bark")
  end)

  test({ "count annotation rides on the last mark's virt_lines" }, function()
    local _, ctx = mk_ctx({ "a", "b" }, 1, 0)
    ghost.show(cfg { show_count = true }, ctx, item_ml_range("L1\nL2", 0, 0, 1, 1), 2, 5)
    local marks = ghost._extmarks()
    T.eq(#marks, 2)
    assert(marks[2].opts.virt_lines, "expected virt_lines for annotation")
    T.eq(marks[2].opts.virt_lines[1][1][1], "  (2/5)")
  end)
end)

T.describe({ "ghost.show control-char fallback" }, function(test)
  test({ "switches to eol when first line has \\t" }, function()
    local buf, ctx = mk_ctx({ "if " }, 1, 3)
    ghost.show(cfg(), ctx, item_of "\tbody", 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    -- nvim reports `win_col` when virt_text_win_col is set (we set both as
    -- a copilot-style "anchor at cursor virtcol" — nvim resolves to win_col).
    T.eq(d.virt_text_pos, "win_col")
    assert(d.virt_text_win_col ~= nil, "expected virt_text_win_col")
  end)

  test({ "uses inline for plain text" }, function()
    local buf, ctx = mk_ctx({ "fido" }, 1, 4)
    ghost.show(cfg(), ctx, item_of "fido_walk", 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "inline")
  end)
end)

T.describe({ "ghost.show multi-line via virt_lines" }, function(test)
  test({ "first line in virt_text, rest in virt_lines" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(cfg(), ctx, item_of "line1\nline2\nline3", 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_text[1][1], "line1")
    assert(d.virt_lines, "expected virt_lines")
    T.eq(d.virt_lines[1][1][1], "line2")
    T.eq(d.virt_lines[2][1][1], "line3")
  end)
end)

T.describe({ "ghost.show cycling annotation" }, function(test)
  test({ "appends (idx/N) when show_count and total > 1" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(cfg { show_count = true }, ctx, item_of "fido", 2, 5)
    local d = mark_details(buf)
    assert(d and d.virt_lines, "expected virt_lines with cycling annotation")
    T.eq(d.virt_lines[#d.virt_lines][1][1], "  (2/5)")
  end)

  test({ "omits annotation when total <= 1" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(cfg { show_count = true }, ctx, item_of "fido", 1, 1)
    local d = mark_details(buf)
    assert(d, "expected an extmark")
    T.eq(d.virt_lines, nil)
  end)
end)

T.describe({ "ghost.clear" }, function(test)
  test({ "removes the extmark" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(cfg(), ctx, item_of "fido", 1, 1)
    assert(mark_text(buf), "ghost should be set")
    ghost.clear(buf)
    T.eq(mark_text(buf), nil)
  end)
end)

T.describe({ "ghost typed-prefix suppression :: multibyte" }, function(test)
  test({ "CJK: ni hao prefix advances by codepoint, not byte" }, function()
    -- "你好世界" — 4 codepoints, 12 bytes (3 bytes each).
    -- User typed "你好" (2 codepoints, 6 bytes); item word "你好世界".
    -- Typed-overlap must report 2 chars and the tail must be "世界" (6 bytes),
    -- not a corrupted mid-byte slice.
    local buf, ctx = mk_ctx({ "你好" }, 1, 6)
    ghost.show(cfg(), ctx, item_of "你好世界", 1, 1)
    local entry = mark_text(buf)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "世界")
  end)

  test({ "emoji prefix: byte-math would mis-split, char-math must not" }, function()
    -- 😀 is 4 UTF-8 bytes. byte-based sub at byte 2 would land mid-codepoint.
    local buf, ctx = mk_ctx({ "😀" }, 1, 4)
    ghost.show(cfg(), ctx, item_of "😀walks", 1, 1)
    local entry = mark_text(buf)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "walks")
  end)
end)

T.describe({ "ghost snippet preview integration" }, function(test)
  -- Parser tests live in producers/snippets/preview.test.lua. Here we only
  -- check that a snippet item's body gets routed through that parser.
  test({ "ghost.show on a snippet item renders preview text, not raw body" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ---@diagnostic disable-next-line: missing-fields
    local snippet_item = {
      word = "fido",
      meta = {
        uid = "x",
        source = "snippets",
        filter = "fido",
        fuzzy = 0,
        snippet = "fido(${1:bone})",
      },
    } --[[@as completions.Item]]
    ghost.show(cfg(), ctx, snippet_item, 1, 1)
    local entry = mark_text(buf)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "fido(bone)")
  end)
end)

