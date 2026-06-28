local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local inserted = require "coq.completions.inserted"
local lsp_util = require "coq.producers.lsp.util"

-- `word_range` runs AFTER `complete()` has already inserted the chosen word, so
-- the fixtures describe the post-insert buffer: `line` is what's on screen,
-- `col` is the (0-based byte) cursor sitting just after `word`.

---@param opts { line: string, col: integer, word?: string, abbr?: string, snippet?: string, lsp?: table }
---@return string out
---@return integer[] span  -- { start_row, start_col, end_row, end_col }
---@return string replacement
local apply = function(opts)
  local buf = TH.scratch_buf(vim.split(opts.line, "\n", { plain = true }))
  local ctx = TH.ctx_of {
    buf = buf,
    pos = { 1, opts.col, opts.col, opts.col },
    iskeyword = vim.bo[buf].iskeyword,
  }
  local item = {
    word = opts.word,
    abbr = opts.abbr,
    meta = { uid = "x", source = "LSP", filter = opts.word or "", fuzzy = 0 },
  }
  local lsp = opts.lsp or {}
  if opts.snippet then
    if lsp.item then
      lsp.item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
      lsp.item.insertText = opts.snippet
    else
      lsp = { item = { insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet, insertText = opts.snippet } }
    end
    item.meta.lsp = lsp
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  local edit = inserted._main_edit(ctx, item, lsp_util.main_edit(lsp.item))
  local enc = lsp.position_encoding or "utf-16"
  vim.lsp.util.apply_text_edits({ edit }, buf, enc)
  local out = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
  vim.api.nvim_buf_delete(buf, { force = true })

  return out,
    {
      edit.range.start.line,
      edit.range.start.character,
      edit.range["end"].line,
      edit.range["end"].character,
    },
    edit.newText
end

---@param enc string
---@param newText string
---@param s integer
---@param insert_end integer
---@param replace_end integer
local insert_replace = function(enc, newText, s, insert_end, replace_end)
  return {
    position_encoding = enc,
    item = {
      textEdit = {
        newText = newText,
        insert = { start = { line = 0, character = s }, ["end"] = { line = 0, character = insert_end } },
        replace = { start = { line = 0, character = s }, ["end"] = { line = 0, character = replace_end } },
      },
    },
  }
end

T.describe({ "inserted.word_range" }, function(test)
  test({ "InsertReplaceEdit.replace is honored verbatim past the cursor" }, function()
    -- Same-row LSP ranges are trusted as-is. InsertReplaceEdit.replace is the
    -- server's explicit "consume this much" contract — past-cursor is intended.
    local out, span, repl = apply {
      line = "abXYZ",
      col = 2,
      word = "ab",
      lsp = insert_replace("utf-8", "ab", 0, 2, 4),
    }
    T.eq(repl, "ab")
    T.eq(span, { 0, 0, 0, 4 })
    T.eq(out, "abZ")
  end)

  test({ "InsertReplaceEdit covering the whole identifier deletes it" }, function()
    -- replace["end"]=5 swallows all of "XYZ" past the cursor — server's call.
    local out = apply {
      line = "abXYZ",
      col = 2,
      word = "ab",
      lsp = insert_replace("utf-8", "ab", 0, 2, 5),
    }
    T.eq(out, "ab")
  end)

  test({ "pure insert (replace end at cursor) deletes nothing past the cursor" }, function()
    local out, span = apply {
      line = "abXYZ",
      col = 2,
      word = "ab",
      lsp = insert_replace("utf-8", "ab", 0, 2, 2),
    }
    T.eq(span, { 0, 0, 0, 2 })
    T.eq(out, "abXYZ")
  end)

  test({ "past-cursor multibyte suffix consumed via utf-16 unit counts" }, function()
    -- suffix "café" — 5 bytes, 4 utf-16 units. replace["end"]=5 → 3 units past
    -- the cursor → delete "caf", keep the multibyte "é".
    local out = apply {
      line = "abcafé",
      col = 2,
      word = "ab",
      lsp = insert_replace("utf-16", "ab", 0, 2, 5),
    }
    T.eq(out, "abé")
  end)

  test({ "plain textEdit (no insert anchor) falls back to the keyword under cursor" }, function()
    -- only a `range`, no `insert`/`replace`: cannot map past the cursor, so the
    -- trailing keyword run "XYZ" is replaced wholesale.
    local out, span = apply {
      line = "abXYZ",
      col = 2,
      word = "ab",
      lsp = {
        position_encoding = "utf-8",
        item = {
          textEdit = {
            newText = "ab",
            range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 99 } },
          },
        },
      },
    }
    T.eq(span, { 0, 0, 0, 5 })
    T.eq(out, "ab")
  end)

  test({ "no textEdit replaces the keyword under the cursor with the word" }, function()
    -- typed "fi", completed to "fido", cursor after "fido"; suffix "do" is part
    -- of the same keyword and gets absorbed.
    local out = apply { line = "fidodo", col = 4, word = "fido" }
    T.eq(out, "fido")
  end)

  test({ "snippet item clears the word range and inserts nothing" }, function()
    local out, _, repl = apply { line = "fido", col = 4, abbr = "fido", snippet = "fido($0)" }
    T.eq(repl, "")
    T.eq(out, "")
  end)
end)

local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

---@param lines string[]
---@return ctx.full, integer buf
local make_ctx = function(lines)
  local buf = TH.scratch_buf(lines)
  local first = lines[1] or ""
  local ctx = TH.ctx_of {
    buf = buf,
    pos = { 1, #first, #first, #first },
    changedtick = vim.b[buf].changedtick,
    iskeyword = vim.bo[buf].iskeyword,
  }
  return ctx, buf
end

---@param buf integer
---@return string[]
local lines_of = function(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, true)
end

-- =============================================================================
-- Scenario-driven span tests.
--
-- Format: scenario(before, word, after, opts?) → final-buffer-string.
--
-- Pre-test state: the buffer holds `before .. word .. after` as if vim had
-- just inserted `word` at the cursor; cursor sits between `word` and `after`.
-- The test runs the full pipeline (`_main_edit` → `apply_text_edits`) and
-- returns the resulting buffer content. Each test asserts what the final
-- buffer should be after our edit logic re-shapes the span around `word`.
-- =============================================================================

---@param before string
---@param word string
---@param after string
---@param opts? { lsp?: table, abbr?: string, snippet?: string }
---@return string
local scenario = function(before, word, after, opts)
  opts = opts or {}
  local content = before .. word .. after
  local buf = TH.scratch_buf(vim.split(content, "\n", { plain = true }))

  local cursor_text = before .. word
  local cursor_lines = vim.split(cursor_text, "\n", { plain = true })
  local row = #cursor_lines
  local col = #cursor_lines[#cursor_lines]

  local ctx = TH.ctx_of {
    buf = buf,
    pos = { row, col, col, col },
    iskeyword = vim.bo[buf].iskeyword,
  }
  local item = {
    word = word,
    abbr = opts.abbr,
    meta = { uid = "x", source = "LSP", filter = word, fuzzy = 0 },
  }
  local lsp = opts.lsp or {}
  if opts.snippet then
    if lsp.item then
      lsp.item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
      lsp.item.insertText = opts.snippet
    else
      lsp = { item = { insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet, insertText = opts.snippet } }
    end
    item.meta.lsp = lsp
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  local edit = inserted._main_edit(ctx, item, lsp_util.main_edit(lsp.item))
  local enc = lsp.position_encoding or "utf-16"
  vim.lsp.util.apply_text_edits({ edit }, buf, enc)
  local out = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
  vim.api.nvim_buf_delete(buf, { force = true })
  return out
end

T.describe({ "inserted span :: |before| |word| |after|" }, function(test)
  -- ---------------------------------------------------------------------------
  -- Keyword / fuzzy: classic "complete the identifier"
  -- ---------------------------------------------------------------------------

  test({ "keyword complete, full identifier: '' fido 'do' → fido" }, function()
    -- user typed `fi`, picked `fido` from mid-`fido` in buffer; trailing `do`
    -- is the rest of the keyword and gets consumed via either rule.
    T.eq(scenario("", "fido", "do"), "fido")
  end)

  test({ "fuzzy cross-replace: '' cat 'do' → cat" }, function()
    -- user had `fix|do`, picked `cat` (zero byte-overlap). Trailing `do` is
    -- still consumed because it's the rest of the identifier — keyword rule
    -- carries this case, overlap rule doesn't.
    T.eq(scenario("", "cat", "do"), "cat")
  end)

  test({ "fuzzy cross-replace with long suffix: '' find_user 'extra' → find_user" }, function()
    T.eq(scenario("", "find_user", "extra"), "find_user")
  end)

  test({ "no trailing identifier: '' fido '' → fido" }, function()
    T.eq(scenario("", "fido", ""), "fido")
  end)

  test({ "trailing non-identifier: '' fido ' rest' → fido rest" }, function()
    T.eq(scenario("", "fido", " rest"), "fido rest")
  end)

  -- ---------------------------------------------------------------------------
  -- Symbol prefix completions (the @param family)
  -- ---------------------------------------------------------------------------

  test({ "symbol overlap left: '((@' @param '' → ((@param" }, function()
    -- byte-overlap on the left consumes the typed `@`; `((` survives because
    -- `(` doesn't prefix-match the word.
    T.eq(scenario("((@", "@param", ""), "((@param")
  end)

  test({ "symbol overlap right: '@' @param '@param' → @param" }, function()
    -- the canonical @|@param case: leading `@` consumed left, the duplicate
    -- `@param` past the cursor consumed right via suffix overlap.
    T.eq(scenario("@", "@param", "@param"), "@param")
  end)

  test({ "inert symbols protected: '((' @param '' → ((@param" }, function()
    -- `(` doesn't match any prefix of `@param`. No left consumption.
    T.eq(scenario("((", "@param", ""), "((@param")
  end)

  test({ "inert symbols both sides: '((' @param '))' → ((@param))" }, function()
    -- closing parens past the cursor: `)` doesn't suffix-match the word; the
    -- keyword run also stops at `)`. No consumption either side.
    T.eq(scenario("((", "@param", "))"), "((@param))")
  end)

  test({ "after-cursor symbol after keyword: '' cat '@thing' → cat@thing" }, function()
    -- after_cursor starts with non-keyword `@`, so leading_keyword stops at 0;
    -- suffix_overlap(cat, @thing) is also 0. Nothing consumed.
    T.eq(scenario("", "cat", "@thing"), "cat@thing")
  end)

  -- ---------------------------------------------------------------------------
  -- Identical / overlapping word with surrounding text
  -- ---------------------------------------------------------------------------

  test({ "longer rightward keyword overlaps: '' param 'param_x' → param" }, function()
    -- the after_cursor `param_x` is one identifier (7 keyword chars).
    -- Keyword rule consumes all 7; result is just the inserted `param`.
    T.eq(scenario("", "param", "param_x"), "param")
  end)

  test({ "identical word repeats both sides: 'fido' fido 'fido' → fidofidofido stays" }, function()
    -- before_inserted "fido" and after_cursor "fido" both fully overlap with
    -- the word. Left: prefix_overlap("fido","fido")=4, trailing_kw=4 → max=4.
    -- start_col=0. Right: leading_kw("fido")=4, suffix_overlap=4 → max=4.
    -- Span 0..(end). Result: single fido.
    T.eq(scenario("fido", "fido", "fido"), "fido")
  end)

  -- ---------------------------------------------------------------------------
  -- Empty edge cases
  -- ---------------------------------------------------------------------------

  test({ "empty word: '' '' '' → ''" }, function()
    T.eq(scenario("", "", ""), "")
  end)

  test({ "empty word with after text: '' '' 'tail' → tail (no consumption)" }, function()
    -- word is empty so no overlap; leading_kw on `tail` is 4 → end_col extends
    -- by 4, but the inserted text is empty, so span 0..4 replaces `tail` with
    -- "". Result: empty.
    T.eq(scenario("", "", "tail"), "")
  end)

  -- ---------------------------------------------------------------------------
  -- Member access / dotted scope — regression for #623, #617, #572.
  -- The dot is non-keyword, so `before_inserted` ending in `.` must not
  -- get consumed by trailing_keyword. The previously-typed prefix has
  -- already been replaced by vim's PUM auto-insert; our span only needs
  -- to cover that auto-insert, not the dot or anything before it.
  -- ---------------------------------------------------------------------------

  test({ "member access, full identifier: 'obj.' method '' → obj.method" }, function()
    -- user typed `obj.met<TAB>`, picked `method`. Pre-PUM:
    -- `obj.met|`. PUM start backed up `met` only (3 chars).
    -- vim inserted `method`, buffer = `obj.method`.
    -- Span must replace just `method` with `method` (no-op).
    T.eq(scenario("obj.", "method", ""), "obj.method")
  end)

  test(
    { "snake_case identifier, dotted scope: 'some_identifier.' completion '' → some_identifier.completion" },
    function()
      -- the canonical #623 example. Underscores are keyword chars; the dot is not.
      -- Span must stop at the dot — not eat into `some_identifier`.
      T.eq(scenario("some_identifier.", "completion", ""), "some_identifier.completion")
    end
  )

  test({ "fuzzy member access mid-identifier: 'obj.' method 'hod' → obj.method" }, function()
    -- user had `obj.met|hod`, picked `method`. Trailing `hod` is the rest of
    -- the identifier under the cursor; leading_keyword rule consumes it.
    T.eq(scenario("obj.", "method", "hod"), "obj.method")
  end)

  -- ---------------------------------------------------------------------------
  -- Pure insert (no surrounding identifier)
  -- ---------------------------------------------------------------------------

  test({ "pure insert at end: 'prefix ' fido '' → prefix fido" }, function()
    T.eq(scenario("prefix ", "fido", ""), "prefix fido")
  end)

  test({ "pure insert with non-keyword before: 'foo ' bar '' → foo bar" }, function()
    -- before_inserted ends in space (whitespace, neither keyword nor symbol);
    -- trailing_kw=0, prefix_overlap=0. No left consumption.
    T.eq(scenario("foo ", "bar", ""), "foo bar")
  end)

  -- ---------------------------------------------------------------------------
  -- Inside brackets / closing-punctuation preservation
  -- ---------------------------------------------------------------------------

  test({ "user's case: '((' @param@ '))' → ((@param@))" }, function()
    -- canonical "complete inside parens, keep the closers" case. The trailing
    -- `))` is symbol but doesn't suffix-match the word; leading_keyword stops
    -- at `)`. Nothing past the cursor is consumed.
    T.eq(scenario("((", "@param@", "))"), "((@param@))")
  end)

  test({ "trailing close-bracket survives keyword completion: '(' fido ')' → (fido)" }, function()
    T.eq(scenario("(", "fido", ")"), "(fido)")
  end)

  test({ "fuzzy inside parens consumes mid-keyword 'x': '(' fido 'x)' → (fido)" }, function()
    -- user had `(fi|x)`, picked `fido`. `x` is the rest of the identifier,
    -- consumed via leading_keyword. The `)` survives — non-keyword + no
    -- suffix overlap with `fido`.
    T.eq(scenario("(", "fido", "x)"), "(fido)")
  end)

  test({ "leading symbol overlap + trailing closers: '((' @param '@param))' → ((@param))" }, function()
    -- before_inserted has `((` (inert symbols), after_cursor starts with the
    -- duplicate `@param` then closers. Suffix_overlap eats `@param`; closers
    -- stay.
    T.eq(scenario("((", "@param", "@param))"), "((@param))")
  end)

  test({ "leading word overlap + trailing closers: '((@param' @param '))' → ((@param))" }, function()
    -- before_inserted ends in `@param`; prefix_overlap eats it. trailing_kw
    -- alone would only eat `param`, not `@`. Closers untouched on the right.
    T.eq(scenario("((@param", "@param", "))"), "((@param))")
  end)

  -- ---------------------------------------------------------------------------
  -- Multi-line buffer (single-line edits don't reach across rows)
  -- ---------------------------------------------------------------------------

  test({ "cursor at end of line, next line preserved: 'foo ' bar '\\nbaz' → 'foo bar\\nbaz'" }, function()
    T.eq(scenario("foo ", "bar", "\nbaz"), "foo bar\nbaz")
  end)

  test({ "trailing identifier on cursor row, next line preserved: '' fido 'do\\nbaz' → 'fido\\nbaz'" }, function()
    -- `do` after cursor is consumed (rest of the identifier on this row);
    -- `\nbaz` on the next row stays untouched.
    T.eq(scenario("", "fido", "do\nbaz"), "fido\nbaz")
  end)

  test({ "prior row preserved when completing on later row: 'line1\\n' fido '' → 'line1\\nfido'" }, function()
    T.eq(scenario("line1\n", "fido", ""), "line1\nfido")
  end)

  test({ "lua_ls-shape: multi-row past-cursor end is clamped, next line preserved" }, function()
    -- The lua_ls bug pattern: cursor on row 0 col 4 (after "fido"), server
    -- returns a textEdit whose range ends on a LATER row. Before the clamp,
    -- this spliced the next line into the cursor row; now end.row > cursor.row
    -- snaps end to (cursor_row, cursor_col), leaving the buffer intact past
    -- the cursor.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "fido",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 2 } },
        },
      },
    }
    T.eq(scenario("", "fido", "\nbar", { lsp = lsp }), "fido\nbar")
  end)

  -- ---------------------------------------------------------------------------
  -- Defensive: out-of-bounds LSP ranges fall back to the heuristic instead of
  -- crashing or producing a garbage byte column.
  -- ---------------------------------------------------------------------------

  test({ "lsp range past buffer end: silently ignored, fallback runs" }, function()
    -- Buffer has 1 line. Server claims to replace through line 99 — we drop
    -- the bad text_edit and use the keyword/overlap fallback. The keyword run
    -- on after_cursor `do` consumes 2.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "ignored",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 99, character = 0 } },
        },
      },
    }
    T.eq(scenario("", "cat", "do", { lsp = lsp }), "cat")
  end)

  test({ "lsp range starts past cursor row: silently ignored" }, function()
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "ignored",
          range = { start = { line = 5, character = 0 }, ["end"] = { line = 5, character = 0 } },
        },
      },
    }
    T.eq(scenario("", "fido", "", { lsp = lsp }), "fido")
  end)

  test({ "lsp range with char past line end: dropped before strict raises" }, function()
    -- the row is valid but range.end.character is far past the line; without
    -- the bounds check, strict str_byteindex would raise. fallback runs.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "ignored",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 999 } },
        },
      },
    }
    T.eq(scenario("", "cat", "do", { lsp = lsp }), "cat")
  end)

  -- ---------------------------------------------------------------------------
  -- Snippet triggers: replacement is empty (snippet body expands separately),
  -- but the span still needs to wipe the trigger entirely — including a
  -- leading symbol that sits OUTSIDE the keyword PUM start.
  -- ---------------------------------------------------------------------------

  test({ "snippet keyword trigger: '' for '' → '' (whole trigger consumed)" }, function()
    T.eq(scenario("", "for", "", { snippet = "for ($1) {$0}" }), "")
  end)

  test({ "snippet keyword trigger eats trailing keyword: '' for 'do' → ''" }, function()
    -- fuzzy `fo|do` → snippet `for`: trailing `do` is the rest of the identifier
    -- under the cursor, consumed via leading_keyword rule. Same as non-snippet.
    T.eq(scenario("", "for", "do", { snippet = "for ($1) {$0}" }), "")
  end)

  test({ "snippet @-prefix trigger: '@' @for '' → '' (leading @ also consumed)" }, function()
    -- regression for Bug 5: pre-PUM `@f|`, PUM start backs up keyword `f` only,
    -- vim leaves `@@for` in buffer. Without match_text=i.word the leading `@`
    -- survives and the snippet expands to `@@for(...)`.
    T.eq(scenario("@", "@for", "", { snippet = "@for ($0)" }), "")
  end)

  test({ "snippet @-prefix trigger with trailing closers: '(@' @for ')' → '()'" }, function()
    -- `(` doesn't prefix-match `@for`, stays. `)` is non-keyword, no suffix
    -- overlap, stays. Span wipes only `@@for`.
    T.eq(scenario("(@", "@for", ")", { snippet = "@for ($0)" }), "()")
  end)

  test({ "snippet trigger with no leading: identical to non-snippet span shape" }, function()
    -- sanity: snippet doesn't perturb the bare keyword case.
    T.eq(scenario("prefix ", "for", "", { snippet = "for ($1) {$0}" }), "prefix ")
  end)

  test({ "snippet trigger ending in `)` doesn't eat trailing `)`" }, function()
    -- `vim.schedule(|)` + LSP `function ()` snippet. Trigger word ends in `)`.
    -- Without suffix_word="" for snippets, suffix_overlap(")", "function ()")
    -- would return 1 and the buffer's closing `)` would be deleted, leaving the
    -- snippet body to expand without the trailing `)` to land on.
    T.eq(scenario("vim.schedule(", "function ()", ")", { snippet = "function ($1)\n\t$0\nend" }), "vim.schedule()")
  end)

  test({ "snippet with LSP range covers only typed prefix: PUM-region end is translated" }, function()
    -- `vim.schedule(fun|)` — user typed "fun", LSP item is "fun()" expanding to
    -- "function ()..." with a textEdit range covering the original 3-char "fun"
    -- in PRE-PUM coords. vim.fn.complete then inserted "fun()" (5 chars), so the
    -- post-insertion buffer has "fun()" at cols 13-17 plus original `)` at
    -- col 18. The LSP's end=16 lands inside the PUM-inserted region
    -- [original_col=13, col=18) and gets translated to col=18; the snippet body
    -- expands at the cursor with no orphan "()" left behind.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "function ($1)",
          range = { start = { line = 0, character = 13 }, ["end"] = { line = 0, character = 16 } },
        },
      },
    }
    T.eq(scenario("vim.schedule(", "fun()", ")", { snippet = "function ()\n\t$0\nend", lsp = lsp }), "vim.schedule()")
  end)

  test({ "PUM-region overlap: LSP start inside inserted region is pulled to its start" }, function()
    -- Mirror of the exitCode end-side case. A buggy server returns
    -- range.start strictly inside the PUM-inserted bytes [original_col, col)
    -- — e.g., start=12 when original_col=10, col=18. Without the start clamp
    -- the apply replaces only the tail of the inserted word and duplicates
    -- the head ("exitCode" → "exexitCode"). With the clamp, start pulls back
    -- to original_col=10 and the apply is a clean no-op.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "exitCode",
          range = { start = { line = 0, character = 12 }, ["end"] = { line = 0, character = 14 } },
        },
      },
    }
    T.eq(scenario("  process.", "exitCode", "", { lsp = lsp }), "  process.exitCode")
  end)

  test({ "PUM-region overlap: LSP textEdit ending pre-PUM-cursor is translated to post-cursor" }, function()
    -- The exitCode duplication regression. Pre-PUM buffer was "  process.exit"
    -- with cursor at col 14. User picks "exitCode" → vim.fn.complete replaces
    -- the typed "exit" (cols 10..14) with "exitCode", buffer becomes
    -- "  process.exitCode" with cursor at col 18. LSP textEdit still references
    -- pre-PUM cols (10, 14) with newText "exitCode" — applied naively, the LSP
    -- replaces "exit" of "exitCode" with "exitCode", leaving "exitCodeCode".
    -- The PUM-region clamp translates end=14 → col=18, making the apply a no-op.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "exitCode",
          range = { start = { line = 0, character = 10 }, ["end"] = { line = 0, character = 14 } },
        },
      },
    }
    T.eq(scenario("  process.", "exitCode", "", { lsp = lsp }), "  process.exitCode")
  end)

  test({ "InsertReplaceEdit with range_end past line end: units clamped" }, function()
    -- both insert.end and range.end on cursor row, but range_end.character
    -- overshoots after_cursor's encoded length. site-3 clamp keeps strict
    -- str_byteindex from raising; the clamp consumes the whole after_cursor.
    local lsp = {
      position_encoding = "utf-8",
      item = {
        textEdit = {
          newText = "cat",
          insert = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } },
          replace = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 999 } },
        },
      },
    }
    T.eq(scenario("", "cat", "do", { lsp = lsp }), "cat")
  end)
end)

T.describe({ "inserted._apply_edits" }, function(test)
  test({ "plain word: replaces the trailing keyword span with item.word" }, function()
    local ctx, buf = make_ctx { "fid" }
    ---@diagnostic disable-next-line: missing-fields
    local item = { word = "fido", meta = { uid = "x", source = "LSP", filter = "fid", fuzzy = 0 } } --[[@as completions.Item]]
    inserted._apply_edits(ctx, item, nil, {})
    T.eq(lines_of(buf), { "fido" })
  end)

  test({ "snippet item: main edit empties the keyword span (snippet expands separately)" }, function()
    local ctx, buf = make_ctx { "fid" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      abbr = "fido",
      meta = {
        uid = "x",
        source = "LSP",
        filter = "fid",
        fuzzy = 0,
        ---@diagnostic disable-next-line: missing-fields
        lsp = { item = { insertTextFormat = 2, insertText = "fido($0)" } },
      },
    } --[[@as completions.Item]]
    inserted._apply_edits(ctx, item, nil, {})
    T.eq(lines_of(buf), { "" })
  end)

  test({ "additionalTextEdits applied alongside the main edit, no row-shift bug" }, function()
    -- INS1 regression: main edit replaces "fid" with 3 lines on row 0;
    -- additional sits on row 2 against the ORIGINAL buffer. Both must land
    -- at their pre-edit coords via apply_text_edits' descending sort.
    local ctx, buf = make_ctx { "fid", "ignored", "leave-me-alone" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = "fid", fuzzy = 0 },
    } --[[@as completions.Item]]
    ---@diagnostic disable-next-line: missing-fields
    local lsp = {
      position_encoding = "utf-16",
      ---@diagnostic disable-next-line: missing-fields
      item = {
        textEdit = {
          newText = "line-1\nline-2\nline-3",
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 3 },
          },
        },
      },
    } --[[@as completions.ItemLspMeta]]
    local additional = {
      {
        newText = "IMPORT",
        range = {
          start = { line = 2, character = 0 },
          ["end"] = { line = 2, character = 0 },
        },
      },
    }
    local original_main = { range = lsp.item.textEdit.range, newText = lsp.item.textEdit.newText }
    inserted._apply_edits(ctx, item, original_main, additional)
    T.eq(lines_of(buf), { "line-1", "line-2", "line-3", "ignored", "IMPORTleave-me-alone" })
  end)
end)

---@param fake fun(ctx: ctx.full, meta: completions.ItemMeta, timeout_ms: integer): completions.ItemLspMeta?
---@return completions.Resolver
local fake_resolver = function(fake)
  ---@diagnostic disable-next-line: missing-fields
  return { resolve = fake } --[[@as completions.Resolver]]
end

---@return config.Settings
local settings_of = function()
  ---@diagnostic disable-next-line: missing-fields
  return { clients = { lsp = { resolve_timeout = 1 } } } --[[@as config.Settings]]
end

T.describe({ "inserted._resolve" }, function(test)
  test({ "falls back to original additionalTextEdits when resolver returns nil" }, function()
    local called = false
    local ctx = make_ctx { "" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = {
        uid = "x",
        source = "LSP",
        filter = "fido",
        fuzzy = 0,
        ---@diagnostic disable-next-line: missing-fields
        lsp = { item = { additionalTextEdits = { { newText = "x", range = {} } } } },
      },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function()
      called = true
      return nil
    end)
    async.scope(function()
      local _, addn = inserted._resolve(settings_of(), ctx, resolver, item.meta)
      T.eq(#addn, 1)
    end)
    T.eq(called, true)
  end)

  test({ "calls resolver and returns enriched additionalTextEdits" }, function()
    local captured_timeout
    local ctx = make_ctx { "" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = "fido", fuzzy = 0, lsp = {} },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function(_, _, timeout_ms)
      captured_timeout = timeout_ms
      return {
        ---@diagnostic disable-next-line: missing-fields
        item = { additionalTextEdits = { { newText = "y", range = {} } } },
      } --[[@as completions.ItemLspMeta]]
    end)
    async.scope(function()
      local _, addn = inserted._resolve(settings_of(), ctx, resolver, item.meta)
      T.eq(#addn, 1)
      T.eq(addn[1].newText, "y")
    end)
    T.eq(captured_timeout, 1000)
  end)

  test({ "returns nil mains when lsp carries no textEdit" }, function()
    local ctx, _ = make_ctx { "" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = "fido", fuzzy = 0, lsp = {} },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function()
      return nil
    end)
    local main_val
    async.scope(function()
      main_val, _ = inserted._resolve(settings_of(), ctx, resolver, item.meta)
    end)
    T.eq(main_val, nil)
  end)
end)
