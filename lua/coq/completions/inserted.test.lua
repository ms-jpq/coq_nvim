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

  local edit = inserted._word_range(ctx, item, lsp)
  vim.api.nvim_buf_set_text(
    buf,
    edit.start_row,
    edit.start_col,
    edit.end_row,
    edit.end_col,
    vim.split(edit.text, "\n", { plain = true })
  )
  local out = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
  vim.api.nvim_buf_delete(buf, { force = true })

  return out, { edit.start_row, edit.start_col, edit.end_row, edit.end_col }, edit.text
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
local edit_ctx = function(o)
  return {
    cursor_row = 0,
    col = o.col or 2,
    after_cursor = o.after_cursor or "",
    kw_before_col = o.kw_before_col or 0,
    kw_after_len = o.kw_after_len or 0,
    start_row = 0,
    start_line = o.start_line or "",
    end_row = o.end_row or 0,
    end_line = o.end_line or "",
  } --[[@as completions.EditCtx]]
end

---@param insert_end integer
---@param replace_end integer
local replace_edit = function(insert_end, replace_end)
  return {
    newText = "",
    insert = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = insert_end } },
    replace = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = replace_end } },
  }
end

T.describe({ "inserted.span" }, function(test)
  test({ "InsertReplaceEdit span ends at replace[end], measured in encoded units" }, function()
    local span =
      inserted._span("utf-8", edit_ctx { col = 2, after_cursor = "XYZ", start_line = "abXYZ" }, replace_edit(2, 4))
    T.eq(span, { start_row = 0, start_col = 0, end_row = 0, end_col = 4 })
  end)

  test({ "pure insert (replace[end] == cursor) deletes nothing past the cursor" }, function()
    local span =
      inserted._span("utf-8", edit_ctx { col = 2, after_cursor = "XYZ", start_line = "abXYZ" }, replace_edit(2, 2))
    T.eq(span.end_col, 2)
  end)

  test({ "no textEdit falls back to the keyword runs flanking the cursor" }, function()
    local span = inserted._span("utf-8", edit_ctx { col = 2, kw_before_col = 0, kw_after_len = 3 }, nil)
    T.eq(span, { start_row = 0, start_col = 0, end_row = 0, end_col = 5 })
  end)
end)
