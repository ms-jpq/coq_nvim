local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local ghost = require "coq.completions.ghost"
local preview = require "coq.producers.snippets.preview"

local NS = vim.api.nvim_create_namespace "coq.ghost"
local DEFAULT_ISKEYWORD = "@,48-57,_,192-255"

-- `bind` wires up the stateful API (M.show, M.clear, etc.) plus event
-- subscriptions. Tests exercise `M.show` directly and inspect `_extmarks`,
-- so we hand bind inert stubs for the nursery and event channels — the
-- subscribers register but never fire.
local stub_chan = {
  subscribe = function()
    return function() end, function()
      return nil
    end
  end,
}
---@type async.Nursery
---@diagnostic disable-next-line: missing-fields, missing-return
local stub_n = { spawn = function() end }
---@type completions.Events
---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
local stub_ev = { completion = stub_chan, leave = stub_chan }

---@type config.Settings
---@diagnostic disable-next-line: missing-fields
local stub_settings = {
  ---@diagnostic disable-next-line: missing-fields
  display = {
    ghost_text = {
      enabled = true,
      highlight_group = "Comment",
    },
  },
  ---@diagnostic disable-next-line: missing-fields
  keymap = {},
}
ghost.bind(stub_n, stub_settings, stub_ev)

local ghost_cfg = stub_settings.display.ghost_text

---@param lines string[]
---@param row integer  -- 1-indexed
---@param col integer  -- 0-indexed byte
---@return integer buf
---@return ctx.full ctx
local mk_ctx = function(lines, row, col)
  local buf = TH.scratch_buf(lines)
  local ctx = TH.ctx_of {
    buf = buf,
    pos = { row, col, col, col },
    line = lines[row] or "",
    iskeyword = DEFAULT_ISKEYWORD,
  }
  return buf, ctx
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
-- ephemeral and only emitted mid-redraw from the current cursor position.
-- Tests recompute by feeding `_extmarks` the cursor col captured at show time.
-- nvim normalizes some keys (eol + virt_text_win_col → "win_col"), so for
-- tests that care about the normalized form we round-trip through a
-- persistent extmark via mark_details.
---@param ghost_settings config.GhostText
---@param buf integer
---@param cursor_col integer
local extmark_opts = function(ghost_settings, buf, cursor_col)
  local s = vim.b[buf].coq_ghost
  if s == nil then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, s.anchor[1], s.anchor[1] + 1, true)[1] or ""
  local first = ghost._extmarks(ghost_settings, s, line, cursor_col)()
  return first and first.opts
end

---@param buf integer
---@param ctx ctx.base
local mark_text = function(buf, ctx)
  local opts = extmark_opts(ghost_cfg, buf, ctx.pos[2])
  return opts and opts.virt_text and opts.virt_text[1]
end

---@param buf integer
---@param ctx ctx.base
local mark_details = function(buf, ctx)
  local opts = extmark_opts(ghost_cfg, buf, ctx.pos[2])
  if not opts then
    return nil
  end
  opts.ephemeral = nil
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, opts)
  local marks = vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
  return marks[1] and marks[1][4]
end

T.describe({ "ghost.show" }, function(test)
  test({ "typed-prefix: renders the untyped tail only" }, function()
    local buf, ctx = mk_ctx({ "./ft" }, 1, 4)
    ghost.show(ctx, item_of "ftplugin")
    local entry = mark_text(buf, ctx)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "plugin")
  end)

  test({ "typed-prefix: nothing to render when typed matches the whole word" }, function()
    local buf, ctx = mk_ctx({ "ftplugin" }, 1, 8)
    ghost.show(ctx, item_of "ftplugin")
    T.eq(mark_text(buf, ctx), nil)
  end)

  test({ "cursor left of anchor: bail rather than paint at cursor" }, function()
    -- show with anchor at col 4; query _extmarks at col 1 (cursor moved back).
    local buf, ctx = mk_ctx({ "./ft" }, 1, 4)
    ghost.show(ctx, item_of "ftplugin")
    local s = vim.b[buf].coq_ghost
    assert(s, "expected ghost state")
    -- _extmarks called with a cursor_col before anchor_col → no mark.
    T.eq(ghost._extmarks(ghost_cfg, s, ctx.line, 1)(), nil)
  end)

  test({ "common-suffix: trims trailing chars already in the buffer" }, function()
    -- cursor between paren chars: user typed "fido(", cursor before ")".
    -- item word "fido()" — the trailing `)` is already in the buffer.
    local buf, ctx = mk_ctx({ "fido()" }, 1, 5)
    ghost.show(ctx, item_of "fido()")
    T.eq(mark_text(buf, ctx), nil)
  end)

  test({ "multibyte: CJK advances by codepoint, not byte" }, function()
    -- "你好世界" — 4 codepoints, 12 bytes. Typed "你好" (6 bytes) → tail "世界".
    local buf, ctx = mk_ctx({ "你好" }, 1, 6)
    ghost.show(ctx, item_of "你好世界")
    local entry = mark_text(buf, ctx)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "世界")
  end)

  test({ "multibyte: emoji prefix never lands mid-codepoint" }, function()
    local buf, ctx = mk_ctx({ "😀" }, 1, 4)
    ghost.show(ctx, item_of "😀walks")
    local entry = mark_text(buf, ctx)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "walks")
  end)

  test({ "subseq cutoff: typed diverges → subseq-stripped tail inline" }, function()
    -- Subseq match consumes 'f'@1 and 'n'@3 in "function" → remaining "ction".
    -- Display: "fn" + "ction" = "fnction".
    local buf, ctx = mk_ctx({ "fn" }, 1, 2)
    ghost.show(ctx, item_of "function")
    local entry = mark_text(buf, ctx)
    assert(entry, "expected an inline extmark")
    T.eq(entry[1], "ction")
  end)

  test({ "multi-line: first line inline, rest as virt_lines" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(ctx, item_of "line1\nline2\nline3")
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text[1][1], "line1")
    assert(d.virt_lines, "expected virt_lines")
    T.eq(d.virt_lines[1][1][1], "line2")
    T.eq(d.virt_lines[2][1][1], "line3")
  end)

  test({ "snippet body routes through the preview parser" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ---@diagnostic disable-next-line: missing-fields
    local snippet_item = {
      word = "fido",
      meta = {
        uid = "x",
        source = "snippets",
        filter = "fido",
        fuzzy = 0,
        ---@diagnostic disable-next-line: missing-fields
        lsp = { item = { insertTextFormat = 2, insertText = "fido(${1:bone})" } },
      },
    } --[[@as completions.Item]]
    ghost.show(ctx, snippet_item)
    local entry = mark_text(buf, ctx)
    assert(entry, "expected an extmark")
    T.eq(entry[1], "fido(" .. preview.L .. "bone" .. preview.R .. ")")
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
    ghost.show(ctx, item_with_range("fido", 0, 4))
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
  end)

  test({ "empty range → overlay (degenerate range = pure insertion)" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(ctx, item_with_range("do", 2, 2))
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
  end)

  test({ "no textEdit → overlay (plain word item)" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(ctx, item_of "fido")
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
  end)

  test({ "tab inside ranged candidate expands; stays overlay" }, function()
    local buf, ctx = mk_ctx({ "" }, 1, 0)
    ghost.show(ctx, item_with_range("\tbody", 0, 5))
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
    T.eq(d.virt_text[1][1], string.rep(" ", vim.bo[buf].tabstop) .. "body")
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
    local buf, ctx = mk_ctx({ "dog", "good", "fido" }, 1, 0)
    ghost.show(ctx, item_ml_range("puppy\nclever\nfido", 0, 0, 2, 4))
    local marks = vim.iter(ghost._extmarks(ghost_cfg, vim.b[buf].coq_ghost, ctx.line, ctx.pos[2])):totable()
    T.eq(#marks, 3)
    -- Anchor is (0, 0); cursor col is 0 too. Marks 2+ overlay at col 0
    -- on rows 1 and 2 (anchor_row + k - 1).
    T.eq(marks[1].opts.virt_text[1][1], "puppy")
    T.eq(marks[1].opts.virt_text_pos, "overlay")
    T.eq(marks[1].row, 0)
    T.eq(marks[2].opts.virt_text[1][1], "clever")
    T.eq(marks[2].opts.virt_text_pos, "overlay")
    T.eq(marks[2].row, 1)
    T.eq(marks[2].col, 0)
    T.eq(marks[3].opts.virt_text[1][1], "fido")
    T.eq(marks[3].row, 2)
    -- No surplus virt_lines on the last mark.
    T.eq(marks[3].opts.virt_lines, nil)
  end)

  test({ "newText has more lines than range: surplus goes into virt_lines" }, function()
    -- 2-row range, 4-line newText → 2 overlays, 2 surplus → virt_lines on mark 2
    local buf, ctx = mk_ctx({ "a", "b" }, 1, 0)
    ghost.show(ctx, item_ml_range("L1\nL2\nL3\nL4", 0, 0, 1, 1))
    local marks = vim.iter(ghost._extmarks(ghost_cfg, vim.b[buf].coq_ghost, ctx.line, ctx.pos[2])):totable()
    T.eq(#marks, 2)
    T.eq(marks[1].opts.virt_text[1][1], "L1")
    T.eq(marks[2].opts.virt_text[1][1], "L2")
    assert(marks[2].opts.virt_lines, "expected virt_lines on last mark")
    T.eq(marks[2].opts.virt_lines[1][1][1], "L3")
    T.eq(marks[2].opts.virt_lines[2][1][1], "L4")
  end)

  test({ "range has more rows than newText: only emit row_overlays for newText lines" }, function()
    -- 3-row range, 1-line newText → 1 mark (anchor), buffer rows 2,3 leak (limitation)
    local buf, ctx = mk_ctx({ "a", "b", "c" }, 1, 0)
    ghost.show(ctx, item_ml_range("once", 0, 0, 2, 1))
    local marks = vim.iter(ghost._extmarks(ghost_cfg, vim.b[buf].coq_ghost, ctx.line, ctx.pos[2])):totable()
    T.eq(#marks, 1)
    T.eq(marks[1].opts.virt_text[1][1], "once")
  end)

  test({ "single-line range, multi-line newText: anchor + virt_lines (no extra overlays)" }, function()
    -- 1-row range stays as single overlay anchor; surplus lines as virt_lines.
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(ctx, item_ml_range("fido\nbark", 0, 0, 0, 2))
    local marks = vim.iter(ghost._extmarks(ghost_cfg, vim.b[buf].coq_ghost, ctx.line, ctx.pos[2])):totable()
    T.eq(#marks, 1)
    T.eq(marks[1].opts.virt_text[1][1], "do") -- "fi" prefix consumed
    assert(marks[1].opts.virt_lines, "expected virt_lines")
    T.eq(marks[1].opts.virt_lines[1][1][1], "bark")
  end)
end)

T.describe({ "ghost.show tab expansion" }, function(test)
  test({ "expands \\t to spaces from anchor column; stays overlay" }, function()
    local buf, ctx = mk_ctx({ "if " }, 1, 3)
    ghost.show(ctx, item_of "\tbody")
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
    local ts = vim.bo[buf].tabstop
    local gap = ts - (3 % ts)
    T.eq(d.virt_text[1][1], string.rep(" ", gap) .. "body")
  end)

  test({ "uses overlay for plain text" }, function()
    local buf, ctx = mk_ctx({ "fido" }, 1, 4)
    ghost.show(ctx, item_of "fido_walk")
    local d = mark_details(buf, ctx)
    assert(d, "expected an extmark")
    T.eq(d.virt_text_pos, "overlay")
  end)
end)

T.describe({ "ghost.clear" }, function(test)
  test({ "removes the extmark" }, function()
    local buf, ctx = mk_ctx({ "fi" }, 1, 2)
    ghost.show(ctx, item_of "fido")
    assert(mark_text(buf, ctx), "ghost should be set")
    ghost.clear(buf)
    T.eq(mark_text(buf, ctx), nil)
  end)
end)

T.describe({ "ghost._remaining" }, function(test)
  ---@type { name: string, typed: string, candidate: string[], head: string, rest: string[] }[]
  local cases = {
    { name = "strict prefix", typed = "wh", candidate = { "while" }, head = "ile", rest = {} },
    { name = "subseq skip in middle", typed = "fn", candidate = { "function" }, head = "ction", rest = {} },
    { name = "subseq with prefix gap", typed = "nvm", candidate = { "nvim_api_*" }, head = "_api_*", rest = {} },
    { name = "longer subseq match", typed = "fnt", candidate = { "function" }, head = "ion", rest = {} },
    -- on bounded-subseq failure, fall back to dropping #typed bytes from the candidate.
    { name = "no chars match → drop #typed", typed = "xy", candidate = { "abc" }, head = "c", rest = {} },
    { name = "empty typed → full body", typed = "", candidate = { "function" }, head = "function", rest = {} },
    { name = "exact match → empty", typed = "while", candidate = { "while" }, head = "", rest = {} },
    {
      name = "partial then unmatched → drop #typed",
      typed = "fnx",
      candidate = { "function" },
      head = "ction",
      rest = {},
    },
    {
      name = "skip budget exceeded → drop #typed",
      typed = "buv",
      candidate = { "nvim_buf_get_var" },
      head = "m_buf_get_var",
      rest = {},
    },
    -- regression: candidate starts with multi-byte `‹` (3 bytes UTF-8).
    -- byte-count fallback would slice mid-codepoint and surface as `<80><b9>`.
    {
      name = "fallback respects codepoint boundary",
      typed = "f",
      candidate = { "‹bone› then" },
      head = "bone› then",
      rest = {},
    },
    {
      name = "multi-line body",
      typed = "fn",
      candidate = { "func", "tion" },
      head = "c",
      rest = { "tion" },
    },
    {
      name = "empty typed multi-line",
      typed = "",
      candidate = { "a", "b", "c" },
      head = "a",
      rest = { "b", "c" },
    },
  }
  for _, c in ipairs(cases) do
    test({ c.name }, function()
      local head, rest = ghost._remaining(c.typed, c.candidate)
      T.eq(head, c.head)
      T.eq(rest, c.rest)
    end)
  end
end)
