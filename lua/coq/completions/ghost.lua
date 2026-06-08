local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local events = require "coq.completions.events"
local inserted = require "coq.completions.inserted"
local txt = require "coq.lib.text"

local NS = vim.api.nvim_create_namespace "coq.ghost"
-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/inline_completion.lua
local LSP_INLINE_NS = vim.api.nvim_create_namespace "nvim.lsp.inline_completion"
local B_KEY = "coq_ghost"

local M = {}

---@class ghost.State
---@field changedtick integer
---@field anchor [integer, integer]
---@field anchor_line string
---@field insert_text string[]
---@field replaces_rows integer?

---@class ghost.Mark
---@field row integer
---@field col integer
---@field opts vim.api.keyset.set_extmark

---@param buf integer
---@return ghost.State?
local function state_of(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  return vim.b[buf][B_KEY]
end

---@param buf integer
M.clear = function(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.b[buf][B_KEY] = nil
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
end

---@param i completions.Item
---@return integer? rows
local function replaces_rows(i)
  local _, r = inserted.text_edit(i.meta.lsp)
  if r == nil or (r.start.line == r["end"].line and r.start.character == r["end"].character) then
    return nil
  end

  return math.max(1, r["end"].line - r.start.line + 1)
end

---@return boolean
local function lsp_inline_active(buf)
  return #vim.api.nvim_buf_get_extmarks(buf, LSP_INLINE_NS, 0, -1, { limit = 1 }) > 0
end

---@param tabstop integer
---@param start_col integer
---@param lines string[]
---@return string[]
M._expand_tabs = function(tabstop, start_col, lines)
  for i, line in ipairs(lines) do
    if string.find(line, "\t", 1, true) then
      local col = (i == 1) and start_col or 0
      local chunks = coroutine.wrap(function()
        local pos = 1
        while true do
          local tab = string.find(line, "\t", pos, true)
          if not tab then
            coroutine.yield(string.sub(line, pos))
            break
          end
          local seg = string.sub(line, pos, tab - 1)
          coroutine.yield(seg)
          col = col + vim.fn.strdisplaywidth(seg)
          local n = tabstop - (col % tabstop)
          coroutine.yield(string.rep(" ", n))
          col = col + n
          pos = tab + 1
        end
      end)
      lines[i] = table.concat(vim.iter(chunks):totable())
    end
  end
  return lines
end

---@param ctx ctx.full
---@param i? completions.Item
M.show = function(ctx, i)
  if i == nil or lsp_inline_active(ctx.buf) then
    return M.clear(ctx.buf)
  end

  local span, e_ctx, _, insert_text = inserted.span(true, ctx, i, i.meta.lsp or {})
  local lines = vim.iter(txt.splitlines(insert_text)):totable()

  if span.start_row == span.end_row and #lines == 1 then
    local trim = span.end_col - e_ctx.col
    lines[1] = string.sub(lines[1], 1, #lines[1] - trim)
  end

  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return M.clear(ctx.buf)
  end

  local row = unpack(ctx.pos)
  local anchor_line = ctx.line
  if span.start_row ~= row - 1 then
    if span.start_row < 0 or span.start_row >= vim.api.nvim_buf_line_count(ctx.buf) then
      return M.clear(ctx.buf)
    end
    anchor_line = vim.api.nvim_buf_get_lines(ctx.buf, span.start_row, span.start_row + 1, true)[1] or ""
  end

  local anchor_vcol = vim.fn.strdisplaywidth(string.sub(anchor_line, 1, span.start_col))
  lines = M._expand_tabs(vim.bo[ctx.buf].tabstop, anchor_vcol, lines)

  ---@type ghost.State
  vim.b[ctx.buf][B_KEY] = {
    changedtick = vim.b[ctx.buf].changedtick,
    anchor = { span.start_row, span.start_col },
    anchor_line = anchor_line,
    insert_text = lines,
    replaces_rows = replaces_rows(i),
  }
end

---@param typed string
---@param candidate string[]
---@return string head
---@return string[] rest
M._remaining = function(typed, candidate)
  local first = candidate[1] or ""
  local head = string.sub(first, txt.subseq_end(typed, first) + 1)
  local rest = { unpack(candidate, 2) }
  return head, rest
end

---@param ghost config.GhostText
---@param s ghost.State
---@param cursor_col integer
---@return fun(): ghost.Mark?
M._extmarks = function(ghost, s, cursor_col)
  return coroutine.wrap(function()
    local anchor_row, anchor_col = unpack(s.anchor)
    if cursor_col < anchor_col then
      return
    end
    local typed = string.sub(s.anchor_line, anchor_col + 1, cursor_col)
    local head, rest = M._remaining(typed, s.insert_text)

    if head == "" and #rest == 0 then
      return
    end

    local lines = vim.list_extend({ head }, rest)
    local pos = s.replaces_rows and "overlay" or "inline"
    local row_overlays = s.replaces_rows and math.min(#lines, s.replaces_rows) or 1

    local virt_lines = vim
      .iter(lines)
      :skip(row_overlays)
      :map(function(l)
        return { { l, ghost.highlight_group } }
      end)
      :totable()

    for k, line_k in vim.iter(lines):take(row_overlays):enumerate() do
      local opts = {
        ephemeral = true,
        virt_text = line_k ~= "" and { { line_k, ghost.highlight_group } } or {},
        virt_text_pos = k == 1 and pos or "overlay",
        hl_mode = "replace",
      }
      if k == row_overlays and #virt_lines > 0 then
        opts.virt_lines = virt_lines
      end

      coroutine.yield {
        row = anchor_row + k - 1,
        col = k == 1 and cursor_col or 0,
        opts = opts,
      }
    end
  end)
end

local nvim_buf_set_extmark = errs.with_reporting(vim.api.nvim_buf_set_extmark)

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
      if s == nil or s.changedtick ~= vim.b[buf].changedtick or lsp_inline_active(buf) then
        return
      end
      local anchor_row = unpack(s.anchor)
      if row ~= anchor_row then
        return
      end
      local win_row, col = unpack(vim.api.nvim_win_get_cursor(win))
      if row ~= win_row - 1 then
        return
      end

      for mark in M._extmarks(settings.display.ghost_text, s, col) do
        nvim_buf_set_extmark(buf, NS, mark.row, mark.col, mark.opts)
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

    atools.scheduled()
    local ci = pum_ev.completed_item
    if ci == nil or ci.word == nil or ci.word == "" then
      return
    end

    if type(ci.user_data) == "table" and ci.user_data.word then
      M.show(context.full(), ci.user_data --[[@as completions.Item]])
    else
      M.clear(vim.api.nvim_get_current_buf())
    end
  end)
end

return M
