local T = require "coq.lib.test"
local inserted = require "coq.completions.inserted"
local tokens = require "coq.lib.index.tokens"

-- `word_range` runs AFTER `complete()` has already inserted the chosen word, so
-- the fixtures describe the post-insert buffer: `line` is what's on screen,
-- `col` is the (0-based byte) cursor sitting just after `word`.

---@param opts { line: string, col: integer, word?: string, abbr?: string, snippet?: string, lsp?: table }
---@return string out
---@return integer[] span  -- { start_row, start_col, end_row, end_col }
---@return string replacement
local apply = function(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, vim.split(opts.line, "\n", { plain = true }))

  -- only buf/pos/iskeyword are read; a full ctx.full is intentionally not built
  ---@type ctx.full
  ---@diagnostic disable-next-line: missing-fields
  local ctx = {
    win = 0,
    buf = buf,
    pos = { 1, opts.col },
    changedtick = 0,
    iskeyword = tokens.parse_charset(vim.bo[buf].iskeyword),
  }
  local item = {
    word = opts.word,
    abbr = opts.abbr,
    meta = { uid = "x", source = "LSP", filter = opts.word or "", fuzzy = 0, snippet = opts.snippet },
  }
  local lsp = opts.lsp or {}

  local edit = inserted._main_edit(ctx, item, lsp)
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
  test({ "InsertReplaceEdit deletes exactly the replace span past the cursor" }, function()
    -- post-insert line "abXYZ", cursor after "ab" (col 2), suffix "XYZ".
    -- replace["end"]=4 → 2 units past the cursor → delete "XY" only, keep "Z".
    -- (the keyword heuristic would have swallowed all of "XYZ".)
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

  test({ "replace span to end of identifier matches the keyword heuristic" }, function()
    -- replace["end"]=5 → 3 units → the whole "XYZ" suffix.
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

  test({ "replace span counts encoded units, not bytes (utf-16)" }, function()
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

-- `_span` is pure: hand-built EditCtx, no buffer. These pin the column math the
-- buffer-level tests above exercise end-to-end.
local DEFAULT_ISKEYWORD = tokens.parse_charset "@,48-57,_,192-255"

local edit_ctx = function(o)
  local col = o.col or 2
  local end_row = o.end_row or 0
  return {
    cursor_row = 0,
    col = col,
    before_inserted = o.before_inserted or "",
    after_cursor = o.after_cursor or "",
    start_line = o.start_line or "",
    end_line = o.end_line or "",
    span = o.span or { start_row = 0, start_col = col, end_row = end_row, end_col = col },
  } --[[@as completions.EditCtx]]
end

T.describe({ "inserted.fallback_span" }, function(test)
  -- `_fallback_span` runs when no LSP range was resolved: pure keyword/overlap
  -- math from EditCtx.
  -- The range-honoring branch lives at the callsite in `_main_edit` and is
  -- exercised by the scenario tests below.
  test({ "fallback uses the keyword runs flanking the cursor" }, function()
    local span = inserted._fallback_span(
      DEFAULT_ISKEYWORD,
      edit_ctx { col = 2, before_inserted = "", after_cursor = "XYZ" },
      "anything"
    )
    -- after_cursor "XYZ" is all keyword chars; leading_keyword consumes all 3.
    T.eq(span, { start_row = 0, start_col = 0, end_row = 0, end_col = 5 })
  end)
end)

local async = require "coq.lib.async"
local atools = require "coq.lib.atools"

---@param lines string[]
---@return ctx.full, integer buf
local make_ctx = function(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  local first = lines[1] or ""
  ---@type ctx.full
  ---@diagnostic disable-next-line: missing-fields
  local ctx = {
    win = 0,
    buf = buf,
    pos = { 1, #first },
    changedtick = vim.b[buf].changedtick,
    iskeyword = tokens.parse_charset(vim.bo[buf].iskeyword),
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
  local buf = vim.api.nvim_create_buf(false, true)
  local content = before .. word .. after
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, vim.split(content, "\n", { plain = true }))

  local cursor_text = before .. word
  local cursor_lines = vim.split(cursor_text, "\n", { plain = true })
  local row = #cursor_lines
  local col = #cursor_lines[#cursor_lines]

  ---@type ctx.full
  ---@diagnostic disable-next-line: missing-fields
  local ctx = {
    win = 0,
    buf = buf,
    pos = { row, col },
    changedtick = 0,
    iskeyword = tokens.parse_charset(vim.bo[buf].iskeyword),
  }
  local item = {
    word = word,
    abbr = opts.abbr,
    meta = { uid = "x", source = "LSP", filter = word, fuzzy = 0, snippet = opts.snippet },
  }
  local lsp = opts.lsp or {}

  local edit = inserted._main_edit(ctx, item, lsp)
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
    inserted._apply_edits(ctx, item, {}, {})
    T.eq(lines_of(buf), { "fido" })
  end)

  test({ "snippet item: main edit empties the keyword span (snippet expands separately)" }, function()
    local ctx, buf = make_ctx { "fid" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      abbr = "fido",
      meta = { uid = "x", source = "LSP", filter = "fid", fuzzy = 0, snippet = "fido($0)" },
    } --[[@as completions.Item]]
    inserted._apply_edits(ctx, item, {}, {})
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
    inserted._apply_edits(ctx, item, lsp, additional)
    T.eq(lines_of(buf), { "line-1", "line-2", "line-3", "ignored", "IMPORTleave-me-alone" })
  end)
end)

---@param fake fun(ctx: ctx.full, item: completions.Item, timeout_ms: integer): completions.ItemLspMeta?
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
  test({ "skips resolver when item already carries additionalTextEdits" }, function()
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
      local lsp, edits = inserted._resolve(settings_of(), ctx, resolver, item)
      assert(lsp, "expected lsp")
      T.eq(#edits, 1)
    end)
    T.eq(called, false)
  end)

  test({ "calls resolver when no additionalTextEdits, returns enriched edits" }, function()
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
      local lsp, edits = inserted._resolve(settings_of(), ctx, resolver, item)
      assert(lsp, "expected lsp")
      T.eq(#edits, 1)
      T.eq(edits[1].newText, "y")
    end)
    T.eq(captured_timeout, 1000)
  end)

  test({ "returns nil when ctx is invalidated post-resolve" }, function()
    local ctx, buf = make_ctx { "" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = "fido", fuzzy = 0, lsp = {} },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function()
      -- mutate the buffer mid-resolve → bumps changedtick → still_valid fails
      atools.scheduled()
      vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "edited" })
      return nil
    end)
    local lsp_val
    async.scope(function()
      lsp_val = inserted._resolve(settings_of(), ctx, resolver, item)
    end)
    T.eq(lsp_val, nil)
  end)
end)
