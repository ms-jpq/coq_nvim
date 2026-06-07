local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local inserted = require "coq.completions.inserted"
local txt = require "coq.lib.text"

local NS = vim.api.nvim_create_namespace "coq.ghost"
local B_KEY = "coq_ghost"

local M = {}

---@class ghost.State
---@field insert_text string  -- full suggestion text (multi-line OK)
---@field anchor_row integer
---@field anchor_col integer  -- col where the suggestion conceptually starts
---@field replaces_rows integer  -- 0 (none), 1 (single-line range), N (multi-line)

---@class ghost.Mark
---@field row_offset integer
---@field col_at_cursor boolean
---@field opts vim.api.keyset.set_extmark

---@param buf integer
---@return ghost.State?
local function state_of(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  return vim.b[buf][B_KEY]
end

---@param i completions.Item
---@return integer rows  -- 0 for non-range, 1 for single-line range, N for multi-line
local function replaces_rows(i)
  local _, r = inserted.text_edit(i.meta.lsp)
  if r == nil then
    return 0
  end
  if r.start.line == r["end"].line and r.start.character == r["end"].character then
    return 0
  end
  return r["end"].line - r.start.line + 1
end

---Slice the remaining ghost text from current cursor position.
---Mirrors blink.cmp / nvim-cmp's pattern: `typed = line[anchor..cursor]`;
---if `insert_text` starts with `typed`, the tail is the rest; otherwise
---return empty (effectively hides the ghost without clearing state).
---@param buf integer
---@param s ghost.State
---@param cursor_col integer
---@return string
local function remaining_at(buf, s, cursor_col)
  if cursor_col < s.anchor_col then
    return ""
  end
  local line = vim.api.nvim_buf_get_lines(buf, s.anchor_row, s.anchor_row + 1, true)[1] or ""
  local typed = string.sub(line, s.anchor_col + 1, cursor_col)
  if string.sub(s.insert_text, 1, #typed) ~= typed then
    return ""
  end
  return string.sub(s.insert_text, #typed + 1)
end

---@param buf integer
M.clear = function(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.b[buf][B_KEY] == nil then
    return
  end
  vim.b[buf][B_KEY] = nil
  vim.api.nvim_exec_autocmds("User", { pattern = "CoqGhostHide", modeline = false })
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
end

---@param ctx ctx.full
---@param i? completions.Item  -- nil clears any active ghost in the buffer
M.show = function(ctx, i)
  -- nil item (no candidates) or LSP inline completion owns the buffer →
  -- clear and stop. Callers can pass `ranked[1]` directly without
  -- branching on "is there anything to show".
  if i == nil or vim.lsp.inline_completion.is_enabled { bufnr = ctx.buf } then
    return M.clear(ctx.buf)
  end

  -- `preview=true`: pre-PUM frame. `edit_ctx` skips the `col - #inserted`
  -- subtraction (the candidate isn't in the buffer yet) and `replace_text`
  -- carries the snippet preview body for snippet items.
  local span, e_ctx, _, insert_text = inserted.span(true, ctx, i, i.meta.lsp or {})
  if insert_text == "" then
    return M.clear(ctx.buf)
  end

  -- Trim trailing chars the edit absorbs from the cursor row. For multi-line
  -- spans the absorbed buffer is on a different row — skip. Single-line case
  -- folds the old hand-rolled `suffix_overlap` trim into a single subtraction
  -- driven by `span.end_col`, so the preview and the would-be edit agree.
  if span.start_row == span.end_row and not string.find(insert_text, "\n", 1, true) then
    local absorbed = span.end_col - e_ctx.col
    if absorbed > 0 then
      insert_text = string.sub(insert_text, 1, #insert_text - absorbed)
    end
  end
  if insert_text == "" then
    return M.clear(ctx.buf)
  end

  ---@type ghost.State
  local s = {
    insert_text = insert_text,
    anchor_row = span.start_row,
    anchor_col = span.start_col,
    replaces_rows = replaces_rows(i),
  }
  vim.b[ctx.buf][B_KEY] = s
  vim.api.nvim_exec_autocmds("User", { pattern = "CoqGhostShow", modeline = false })
end

---Build the list of extmarks to emit during redraw.
---@param ghost config.GhostText
---@param buf integer
---@param cursor_col integer  -- 0-based byte col, recomputed each frame
---@return ghost.Mark[]
M._extmarks = function(ghost, buf, cursor_col)
  local s = state_of(buf)
  if s == nil then
    return {}
  end
  local remaining = remaining_at(buf, s, cursor_col or s.anchor_col)
  if remaining == "" then
    return {}
  end
  local lines = vim.iter(txt.splitlines(remaining)):totable()
  local line1 = lines[1] or ""
  if line1 == "" and #lines <= 1 then
    return {}
  end

  -- eol when control chars; overlay when LSP item replaces buffer text;
  -- inline otherwise (pure insertion preview).
  local has_ctrl = string.find(line1, "%c") ~= nil
  local has_range = s.replaces_rows > 0
  local pos = (has_ctrl and "eol") or (has_range and "overlay") or "inline"
  local hl = ghost.highlight_group

  -- Distribute newText lines across buffer rows.
  -- - Range items spanning N rows overlay min(N, #lines) consecutive rows.
  -- - Non-range items (or control-char fallback) put line 1 on the anchor
  --   row, rest as virt_lines below — pure insertion semantic.
  local can_per_row = has_range and not has_ctrl
  local row_overlays = can_per_row and math.min(#lines, s.replaces_rows) or 1

  local marks = {}

  local anchor_opts = {
    ephemeral = true,
    virt_text = line1 ~= "" and { { line1, hl } } or {},
    virt_text_pos = pos,
    hl_mode = "replace",
  }
  if pos == "eol" then
    anchor_opts.virt_text_win_col = vim.fn.virtcol "." - 1
  end
  marks[1] = { row_offset = 0, col_at_cursor = true, opts = anchor_opts }

  for k = 2, row_overlays do
    table.insert(marks, {
      row_offset = k - 1,
      col_at_cursor = false,
      opts = {
        ephemeral = true,
        virt_text = lines[k] ~= "" and { { lines[k], hl } } or {},
        virt_text_pos = "overlay",
        hl_mode = "replace",
      },
    })
  end

  -- Surplus newText lines past the range → virt_lines on the last mark.
  if #lines > row_overlays then
    local virt_lines = {}
    for k = row_overlays + 1, #lines do
      table.insert(virt_lines, { { lines[k], hl } })
    end
    marks[#marks].opts.virt_lines = virt_lines
  end

  return marks
end

---@param ghost config.GhostText
---@param buf integer
---@param cursor_col integer
M._extmark_opts = function(ghost, buf, cursor_col)
  local marks = M._extmarks(ghost, buf, cursor_col)
  return marks[1] and marks[1].opts
end

---@param n async.Nursery
---@param settings config.Settings
---@param ev completions.Events
M.bind = function(n, settings, ev)
  vim.api.nvim_set_decoration_provider(NS, {
    on_win = function(_, _, buf)
      return state_of(buf) ~= nil
    end,
    on_line = function(_, win, buf, row)
      local s = state_of(buf)
      if s == nil or row ~= s.anchor_row then
        return
      end
      local cur = vim.api.nvim_win_get_cursor(win)
      if row ~= cur[1] - 1 then
        return
      end
      for _, mark in ipairs(M._extmarks(settings.display.ghost_text, buf, cur[2])) do
        local r = s.anchor_row + mark.row_offset
        local c = mark.col_at_cursor and cur[2] or 0
        pcall(vim.api.nvim_buf_set_extmark, buf, NS, r, c, mark.opts)
      end
    end,
  })

  events.subscribe_latest(n, ev.leave, function(buf)
    atools.scheduled()
    M.clear(buf)
  end)

  events.subscribe_latest(n, ev.pum, function(pum_ev)
    if pum_ev.kind ~= "changed" then
      return
    end
    local ud = pum_ev.completed_item and pum_ev.completed_item.user_data
    if type(ud) == "table" and ud.word then
      M.show(context.full(), ud --[[@as completions.Item]])
    end
  end)
end

return M
