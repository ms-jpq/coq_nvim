local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local events = require "coq.completions.events"
local inserted = require "coq.completions.inserted"
local lib = require "coq.lib"
local txt = require "coq.lib.text"

local NS = vim.api.nvim_create_namespace "coq.ghost"

local M = {}

---@param i completions.Item
local function has_replacement_range(i)
  local _, r = inserted.text_edit(i.meta.lsp)
  return r ~= nil and not (r.start.line == r["end"].line and r.start.character == r["end"].character)
end

---@param i completions.Item
local function insertion_text(i)
  local text_edit, range = inserted.text_edit(i.meta.lsp)
  return inserted.replacement_text(true, i, range, text_edit)
end

-- Stubs — overridden by `bind`. Calling them before bind is a no-op rather
-- than a nil-method error, so importers (notably `insertion.complete`) can
-- safely call `ghost.show` without ordering ceremony.
M.show = lib.noop
M.clear = lib.noop
M._extmark_opts = lib.noop

---@param n? async.Nursery
---@param settings config.Settings
---@param ev? completions.Events
M.bind = function(n, settings, ev)
  local ghost_cfg = settings.display.ghost_text
  if not ghost_cfg.enabled then
    return
  end

  ---@class ghost.State
  ---@field buf integer?
  ---@field remaining string
  ---@field anchor_row integer
  ---@field has_range boolean
  ---@field idx integer
  ---@field total integer
  ---@field ghost config.GhostText?
  local state = {
    buf = nil,
    remaining = "",
    anchor_row = 0,
    has_range = false,
    idx = 1,
    total = 0,
    ghost = nil,
  }

  M._extmark_opts = function()
    local g = state.ghost
    if g == nil or state.remaining == "" then
      return nil
    end
    local lines = vim.iter(txt.splitlines(state.remaining)):totable()
    local line1 = lines[1] or ""
    if line1 == "" and #lines <= 1 then
      return nil
    end

    -- eol when control chars; overlay when LSP item replaces buffer text;
    -- inline otherwise (pure insertion preview).
    local has_ctrl = string.find(line1, "%c") ~= nil
    local pos = (has_ctrl and "eol") or (state.has_range and "overlay") or "inline"
    local hl = g.highlight_group

    local virt_lines = {}
    for k = 2, #lines do
      table.insert(virt_lines, { { lines[k], hl } })
    end
    if g.show_count and state.total > 1 then
      table.insert(virt_lines, {
        { string.format("  (%d/%d)", state.idx, state.total), g.count_highlight_group or hl },
      })
    end

    local opts = {
      ephemeral = true,
      virt_text = line1 ~= "" and { { line1, hl } } or {},
      virt_text_pos = pos,
      hl_mode = "replace",
    }
    if pos == "eol" then
      opts.virt_text_win_col = vim.fn.virtcol "." - 1
    end
    if #virt_lines > 0 then
      opts.virt_lines = virt_lines
    end
    return opts
  end

  M.clear = function(buf)
    if state.buf == nil then
      return
    end
    state.buf, state.remaining, state.has_range, state.ghost = nil, "", false, nil
    vim.api.nvim_exec_autocmds("User", { pattern = "CoqGhostHide", modeline = false })
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    end
  end

  ---@param ghost config.GhostText
  ---@param ctx ctx.base
  ---@param i completions.Item
  ---@param idx? integer
  ---@param total? integer
  M.show = function(ghost, ctx, i, idx, total)
    -- Defer to `vim.lsp.inline_completion` when the buffer has it enabled.
    if not ghost.enabled or vim.lsp.inline_completion.is_enabled { bufnr = ctx.buf } then
      return M.clear(ctx.buf)
    end
    local raw = insertion_text(i)
    if raw == "" then
      return M.clear(ctx.buf)
    end

    local row, col = unpack(ctx.pos)
    local line = vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, true)[1] or ""
    local before, after = string.sub(line, 1, col), string.sub(line, col + 1)
    -- Same overlap math `inserted._fallback_span` uses to compute its edit
    -- span — re-exported from `inserted` so the shared semantics are visible.
    local tail = string.sub(raw, inserted.prefix_overlap(before, raw) + 1)
    tail = string.sub(tail, 1, #tail - inserted.suffix_overlap(after, tail))
    if tail == "" then
      return M.clear(ctx.buf)
    end

    state.buf = ctx.buf
    state.remaining = tail
    state.anchor_row = row - 1
    state.has_range = has_replacement_range(i)
    state.idx = idx or 1
    state.total = total or 0
    state.ghost = ghost
    vim.api.nvim_exec_autocmds("User", { pattern = "CoqGhostShow", modeline = false })
  end

  -- Decoration provider: nvim invokes our hooks during each redraw, only for
  -- visible windows/lines. State is the truth; render is derived.
  vim.api.nvim_set_decoration_provider(NS, {
    on_win = function(_, _, buf)
      return state.buf == buf and state.remaining ~= ""
    end,
    on_line = function(_, win, buf, row)
      if state.buf ~= buf or row ~= state.anchor_row then
        return
      end
      local cur = vim.api.nvim_win_get_cursor(win)
      if row ~= cur[1] - 1 then
        return
      end
      local opts = M._extmark_opts()
      if opts then
        pcall(vim.api.nvim_buf_set_extmark, buf, NS, row, cur[2], opts)
      end
    end,
  })

  local advance_handled = false
  vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
    group = lib.group,
    callback = function(args)
      if state.buf ~= args.buf or state.remaining == "" then
        return
      end
      local ch = vim.v.char
      if type(ch) ~= "string" or ch == "" then
        return
      end
      advance_handled = true
      if string.sub(state.remaining, 1, #ch) ~= ch then
        return M.clear(args.buf)
      end
      state.remaining = string.sub(state.remaining, #ch + 1)
      if state.remaining == "" then
        M.clear(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChangedI" }, {
    group = lib.group,
    callback = function(args)
      if advance_handled then
        advance_handled = false
      elseif state.buf == args.buf then
        M.clear(args.buf)
      end
    end,
  })

  -- Event subscriptions — skipped when n/ev are nil (test path).
  if n and ev then
    events.subscribe_latest(n, ev.pum, function(pum_ev)
      if pum_ev.kind ~= "changed" then
        return
      end
      local ud = pum_ev.completed_item and pum_ev.completed_item.user_data
      if type(ud) == "table" and ud.word then
        M.show(ghost_cfg, context.base(), ud --[[@as completions.Item]])
      end
    end)
    events.subscribe_latest(n, ev.leave, function()
      atools.scheduled()
      M.clear(state.buf)
    end)
  end
end

return M
