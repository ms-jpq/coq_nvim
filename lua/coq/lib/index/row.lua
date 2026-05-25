local M = {}

-- A completion candidate: one popup-menu row.
-- Rows cross the worker -> main boundary as mpack data, so every field must be
-- plain (string / number / boolean / table) -- no functions, no handles.
M.new = function(spec)
  return {
    source = spec.source, -- source id: scoring prior, resolve routing, dedup

    -- display (nvim complete-item fields)
    abbr = spec.abbr, -- primary display text
    abbr_hlgroup = spec.abbr_hlgroup, -- abbr highlight (e.g. DiagnosticDeprecated)
    kind = spec.kind, -- display text (the db normalizes LSP kind numbers)
    kind_hlgroup = spec.kind_hlgroup, -- kind highlight (e.g. a color-swatch group)
    menu = spec.menu, -- short secondary text (pum menu column)
    info = spec.info, -- long preview text; usually filled post-resolve

    -- match: scored against the query token (prefix-gather + fuzzy rerank)
    filter = spec.filter or spec.abbr,

    -- accept: applied to the buffer
    word = spec.word or spec.abbr, -- inserted text; a snippet to expand when `snippet`
    snippet = spec.snippet or false,
    range = spec.range, -- replace span on the cursor line, byte cols {s, e}; nil => query range
    edits = spec.edits, -- additionalTextEdits (auto-import), byte cols

    -- lazy: fetched on selection via completionItem/resolve(source, data)
    resolvable = spec.resolvable or false,
    data = spec.data, -- opaque source payload (raw item) for resolve/confirm
  }
end

-- Rerank metric: how well `token` matches this row. Higher is better; nil drops
-- the row (token is not a subsequence). Per-row-independent, so a partial top-k
-- is correct before every source has finished streaming.
M.score = function(row, token)
  if token == "" then
    return 0
  end

  local hay, need = row.filter, token
  local hn, nn = #hay, #need
  local ni, run, score = 1, 0, 0

  for hi = 1, hn do
    if ni > nn then
      break
    end
    local hc = hay:sub(hi, hi)
    local nc = need:sub(ni, ni)
    if hc:lower() == nc:lower() then
      local prev = hi > 1 and hay:sub(hi - 1, hi - 1) or ""
      local boundary = hi == 1
        or prev == "_"
        or prev == "."
        or prev == "/"
        or prev == "-"
        or (prev:match "%l" ~= nil and hc:match "%u" ~= nil)

      run = run + 1
      score = score + run -- contiguous run
      if boundary then
        score = score + 3 -- prefix / camelCase / separator boundary
      end
      if hc == nc then
        score = score + 1 -- exact case
      end
      ni = ni + 1
    else
      run = 0
    end
  end

  if ni <= nn then
    return nil
  end

  return score - hn * 0.01 -- tie-break toward tighter matches
end

M.to_item = function(row)
  return {
    dup = 1,
    word = row.snippet and row.abbr or row.word,
    abbr = row.abbr,
    abbr_hlgroup = row.abbr_hlgroup,
    menu = row.menu,
    info = row.info,
    kind = row.kind,
    kind_hlgroup = row.kind_hlgroup,
    user_data = row,
  }
end

return M
