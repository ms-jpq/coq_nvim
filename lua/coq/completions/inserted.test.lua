local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local inserted = require "coq.completions.inserted"
local lsp_util = require "coq.producers.lsp.util"

T.describe({ "inserted._shift_edits" }, function(test)
  for _, case in ipairs {
    { "identity", { 2, 4 }, { 1, 2 }, { 2, 4 } },
    { "before replacement", { 0, 1 }, { 2, 3 }, { 0, 1 } },
    { "at replacement end", { 1, 2 }, { 2, 3 }, { 2, 3 } },
    { "same-line suffix", { 1, 4 }, { 2, 3 }, { 2, 5 } },
    { "following line", { 3, 4 }, { 2, 3 }, { 4, 4 } },
    { "shorter replacement", { 1, 4 }, { 1, 0 }, { 1, 2 } },
  } do
    test({ case[1] }, function()
      local position = function(pair)
        return { line = pair[1], character = pair[2] }
      end
      local edits = {
        { newText = "fido", range = { start = position(case[2]), ["end"] = position(case[2]) } },
      }
      local original = vim.deepcopy(edits)
      local shifted = inserted._shift_edits(edits, { before = position { 1, 2 }, after = position(case[3]) })
      T.eq(shifted, {
        { newText = "fido", range = { start = position(case[4]), ["end"] = position(case[4]) } },
      })
      T.eq(edits, original)
    end)
  end
end)

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
    meta = { uid = "x", source = "LSP", filter = { opts.word or "" }, fuzzy = 0 },
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
    local out = apply {
      line = "abcafé",
      col = 2,
      word = "ab",
      lsp = insert_replace("utf-16", "ab", 0, 2, 5),
    }
    T.eq(out, "abé")
  end)

  test({ "plain textEdit (no insert anchor) falls back to the keyword under cursor" }, function()
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
    meta = { uid = "x", source = "LSP", filter = { word }, fuzzy = 0 },
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
  test({ "keyword complete, full identifier: '' fido 'do' → fido" }, function()
    T.eq(scenario("", "fido", "do"), "fido")
  end)

  test({ "fuzzy cross-replace: '' cat 'do' → cat" }, function()
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

  test({ "symbol overlap left: '((@' @param '' → ((@param" }, function()
    T.eq(scenario("((@", "@param", ""), "((@param")
  end)

  test({ "symbol overlap right: '@' @param '@param' → @param" }, function()
    T.eq(scenario("@", "@param", "@param"), "@param")
  end)

  test({ "inert symbols protected: '((' @param '' → ((@param" }, function()
    T.eq(scenario("((", "@param", ""), "((@param")
  end)

  test({ "inert symbols both sides: '((' @param '))' → ((@param))" }, function()
    T.eq(scenario("((", "@param", "))"), "((@param))")
  end)

  test({ "after-cursor symbol after keyword: '' cat '@thing' → cat@thing" }, function()
    T.eq(scenario("", "cat", "@thing"), "cat@thing")
  end)

  test({ "longer rightward keyword overlaps: '' param 'param_x' → param" }, function()
    T.eq(scenario("", "param", "param_x"), "param")
  end)

  test({ "identical word repeats both sides: 'fido' fido 'fido' → fidofidofido stays" }, function()
    T.eq(scenario("fido", "fido", "fido"), "fido")
  end)

  test({ "empty word: '' '' '' → ''" }, function()
    T.eq(scenario("", "", ""), "")
  end)

  test({ "empty word with after text: '' '' 'tail' → tail (no consumption)" }, function()
    T.eq(scenario("", "", "tail"), "")
  end)

  test({ "member access, full identifier: 'obj.' method '' → obj.method" }, function()
    T.eq(scenario("obj.", "method", ""), "obj.method")
  end)

  test(
    { "snake_case identifier, dotted scope: 'some_identifier.' completion '' → some_identifier.completion" },
    function()
      T.eq(scenario("some_identifier.", "completion", ""), "some_identifier.completion")
    end
  )

  test({ "fuzzy member access mid-identifier: 'obj.' method 'hod' → obj.method" }, function()
    T.eq(scenario("obj.", "method", "hod"), "obj.method")
  end)

  test({ "pure insert at end: 'prefix ' fido '' → prefix fido" }, function()
    T.eq(scenario("prefix ", "fido", ""), "prefix fido")
  end)

  test({ "pure insert with non-keyword before: 'foo ' bar '' → foo bar" }, function()
    T.eq(scenario("foo ", "bar", ""), "foo bar")
  end)

  test({ "user's case: '((' @param@ '))' → ((@param@))" }, function()
    T.eq(scenario("((", "@param@", "))"), "((@param@))")
  end)

  test({ "trailing close-bracket survives keyword completion: '(' fido ')' → (fido)" }, function()
    T.eq(scenario("(", "fido", ")"), "(fido)")
  end)

  test({ "fuzzy inside parens consumes mid-keyword 'x': '(' fido 'x)' → (fido)" }, function()
    T.eq(scenario("(", "fido", "x)"), "(fido)")
  end)

  test({ "leading symbol overlap + trailing closers: '((' @param '@param))' → ((@param))" }, function()
    T.eq(scenario("((", "@param", "@param))"), "((@param))")
  end)

  test({ "leading word overlap + trailing closers: '((@param' @param '))' → ((@param))" }, function()
    T.eq(scenario("((@param", "@param", "))"), "((@param))")
  end)

  test({ "cursor at end of line, next line preserved: 'foo ' bar '\\nbaz' → 'foo bar\\nbaz'" }, function()
    T.eq(scenario("foo ", "bar", "\nbaz"), "foo bar\nbaz")
  end)

  test({ "trailing identifier on cursor row, next line preserved: '' fido 'do\\nbaz' → 'fido\\nbaz'" }, function()
    T.eq(scenario("", "fido", "do\nbaz"), "fido\nbaz")
  end)

  test({ "prior row preserved when completing on later row: 'line1\\n' fido '' → 'line1\\nfido'" }, function()
    T.eq(scenario("line1\n", "fido", ""), "line1\nfido")
  end)

  test({ "lua_ls-shape: multi-row past-cursor end is clamped, next line preserved" }, function()
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

  test({ "lsp range past buffer end: silently ignored, fallback runs" }, function()
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

  test({ "snippet keyword trigger: '' for '' → '' (whole trigger consumed)" }, function()
    T.eq(scenario("", "for", "", { snippet = "for ($1) {$0}" }), "")
  end)

  test({ "snippet keyword trigger eats trailing keyword: '' for 'do' → ''" }, function()
    T.eq(scenario("", "for", "do", { snippet = "for ($1) {$0}" }), "")
  end)

  test({ "snippet @-prefix trigger: '@' @for '' → '' (leading @ also consumed)" }, function()
    T.eq(scenario("@", "@for", "", { snippet = "@for ($0)" }), "")
  end)

  test({ "snippet @-prefix trigger with trailing closers: '(@' @for ')' → '()'" }, function()
    T.eq(scenario("(@", "@for", ")", { snippet = "@for ($0)" }), "()")
  end)

  test({ "snippet trigger with no leading: identical to non-snippet span shape" }, function()
    T.eq(scenario("prefix ", "for", "", { snippet = "for ($1) {$0}" }), "prefix ")
  end)

  test({ "snippet trigger ending in `)` doesn't eat trailing `)`" }, function()
    T.eq(scenario("vim.schedule(", "function ()", ")", { snippet = "function ($1)\n\t$0\nend" }), "vim.schedule()")
  end)

  test({ "multiline snippet trigger does not crash original-column detection" }, function()
    local ok = pcall(function()
      scenario("", "fido\nspot", "", { snippet = "fido\n\t$0" })
    end)
    T.eq(ok, true)
  end)

  test({ "snippet with LSP range covers only typed prefix: PUM-region end is translated" }, function()
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
    local item = { word = "fido", meta = { uid = "x", source = "LSP", filter = { "fid" }, fuzzy = 0 } } --[[@as completions.Item]]
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
        filter = { "fid" },
        fuzzy = 0,
        ---@diagnostic disable-next-line: missing-fields
        lsp = { item = { insertTextFormat = 2, insertText = "fido($0)" } },
      },
    } --[[@as completions.Item]]
    inserted._apply_edits(ctx, item, nil, {})
    T.eq(lines_of(buf), { "" })
  end)

  test({ "additionalTextEdits applied alongside the main edit, no row-shift bug" }, function()
    local ctx, buf = make_ctx { "fid", "ignored", "leave-me-alone" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = { "fid" }, fuzzy = 0 },
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
        filter = { "fido" },
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
      local resolved = inserted._resolve(settings_of(), ctx, resolver, item.meta)
      T.eq(resolved, item.meta.lsp)
      local addn = lsp_util.addn_edits(resolved and resolved.item)
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
      meta = { uid = "x", source = "LSP", filter = { "fido" }, fuzzy = 0, lsp = {} },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function(_, _, timeout_ms)
      captured_timeout = timeout_ms
      return {
        ---@diagnostic disable-next-line: missing-fields
        item = { additionalTextEdits = { { newText = "y", range = {} } } },
      } --[[@as completions.ItemLspMeta]]
    end)
    async.scope(function()
      local resolved = inserted._resolve(settings_of(), ctx, resolver, item.meta)
      local addn = lsp_util.addn_edits(resolved and resolved.item)
      T.eq(#addn, 1)
      T.eq(addn[1].newText, "y")
    end)
    T.eq(captured_timeout, 1000)
  end)

  test({ "empty LSP metadata has no main edit" }, function()
    local ctx, _ = make_ctx { "" }
    ---@diagnostic disable-next-line: missing-fields
    local item = {
      word = "fido",
      meta = { uid = "x", source = "LSP", filter = { "fido" }, fuzzy = 0, lsp = {} },
    } --[[@as completions.Item]]
    local resolver = fake_resolver(function()
      return nil
    end)
    local resolved
    async.scope(function()
      resolved = inserted._resolve(settings_of(), ctx, resolver, item.meta)
    end)
    T.eq(lsp_util.main_edit(resolved and resolved.item), nil)
  end)
end)
