local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local errs = require "coq.lib.errs"
local events = require "coq.completions.events"
local inserted = require "coq.completions.inserted"
local lsp_util = require "coq.producers.lsp.util"
local txt = require "coq.lib.text"

local NS = vim.api.nvim_create_namespace "coq.ghost"
-- https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/inline_completion.lua
local LSP_INLINE_NS = vim.api.nvim_create_namespace "nvim.lsp.inline_completion"
local B_KEY = "coq_ghost"
local MAX_SKIP = 2

local M = {}

---@class ghost.State
---@field anchor [integer, integer]
---@field insert_text string[]
---@field replaces_rows integer?
---@field inline boolean

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

local clear_ns = function(buf)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
end

---@param i completions.Item
---@return integer? rows
local function replaces_rows(i)
  local main = lsp_util.main_edit(i.meta.lsp and i.meta.lsp.item)
  local r = main and main.range
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
  return vim
    .iter(lines)
    :enumerate()
    :map(function(i, line)
      if not string.find(line, "\t", 1, true) then
        return line
      end

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
      return table.concat(vim.iter(chunks):totable())
    end)
    :totable()
end

---@type fun(buf: integer, lo: integer, hi: integer)
local invalidate = vim.api.nvim__redraw
    and function(buf, lo, hi)
      vim.api.nvim__redraw {
        valid = false,
        buf = buf,
        range = { lo, hi },
      }
    end
  or function(buf, lo, _)
    local id = vim.api.nvim_buf_set_extmark(buf, NS, lo, 0, {})
    vim.api.nvim_buf_del_extmark(buf, NS, id)
  end

---@param s ghost.State
---@return integer lo
---@return integer hi
local bounds = function(s)
  local row = unpack(s.anchor)
  return row, row + math.max(#s.insert_text, s.replaces_rows or 1)
end

---@param buf integer
---@param next ghost.State?
local replace = function(buf, next)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local old = state_of(buf)
  vim.b[buf][B_KEY] = next

  if next == nil then
    clear_ns(buf)
  end

  if old == nil and next == nil then
    return
  end

  local lo, hi
  if old ~= nil then
    lo, hi = bounds(old)
  end
  if next ~= nil then
    local next_lo, next_hi = bounds(next)
    lo = lo and math.min(lo, next_lo) or next_lo
    hi = hi and math.max(hi, next_hi) or next_hi
  end
  invalidate(buf, lo, hi)
end

---@param buf integer
M.clear = function(buf)
  replace(buf, nil)
end

---@param ctx ctx.full
---@param i? completions.Item
M.show = function(ctx, i)
  if i == nil or lsp_inline_active(ctx.buf) then
    return M.clear(ctx.buf)
  end

  local span, e_ctx, insert_text = inserted.span(true, ctx, i, lsp_util.main_edit(i.meta.lsp and i.meta.lsp.item))
  local lines = vim.iter(txt.splitlines(insert_text)):totable()

  if span.start_row == span.end_row then
    local trim = math.max(0, span.end_col - e_ctx.col)
    lines[1] = txt.truncate_to_codepoint(lines[1], #lines[1] - trim)
  end

  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return M.clear(ctx.buf)
  end

  if span.start_row < 0 or span.start_row >= vim.api.nvim_buf_line_count(ctx.buf) then
    return M.clear(ctx.buf)
  end
  local anchor_line = unpack(vim.api.nvim_buf_get_lines(ctx.buf, span.start_row, span.start_row + 1, true)) or ""

  local anchor_vcol = vim.fn.strdisplaywidth(string.sub(anchor_line, 1, span.start_col))
  lines = M._expand_tabs(vim.bo[ctx.buf].tabstop, anchor_vcol, lines)

  ---@type ghost.State
  replace(ctx.buf, {
    anchor = { span.start_row, span.start_col },
    insert_text = lines,
    replaces_rows = replaces_rows(i),
    inline = span.start_row == e_ctx.cursor_row and span.end_row == e_ctx.cursor_row and span.end_col == e_ctx.col,
  })
end

---@param typed string
---@param str string
---@return integer?
local bounded_subseq_end = function(typed, str)
  local j = 0
  for i = 1, #typed do
    local c = string.byte(typed, i)
    local stop = math.min(j + 1 + MAX_SKIP, #str)
    local found = false
    for k = j + 1, stop do
      if string.byte(str, k) == c then
        j = k
        found = true
        break
      end
    end
    if not found then
      return nil
    end
  end
  return j
end

---@param typed string
---@param candidate string[]
---@return string head
---@return string[] rest
M._remaining = function(typed, candidate)
  local first = candidate[1] or ""
  local j = bounded_subseq_end(typed, first)
  if j == nil then
    j = vim.fn.byteidx(first, vim.fn.strchars(typed))
    if j < 0 then
      j = #first
    end
  end
  local head = string.sub(first, j + 1)
  local rest = { unpack(candidate, 2) }
  return head, rest
end

---@param ghost config.GhostText
---@param s ghost.State
---@param line string
---@param cursor_col integer
---@return fun(): ghost.Mark?
M._extmarks = function(ghost, s, line, cursor_col)
  return coroutine.wrap(function()
    local anchor_row, anchor_col = unpack(s.anchor)
    if cursor_col < anchor_col then
      return
    end
    local typed = string.sub(line, anchor_col + 1, cursor_col)
    local head, rest = M._remaining(typed, s.insert_text)

    if head == "" and #rest == 0 then
      return
    end

    local lines = vim.list_extend({ head }, rest)
    local row_overlays = s.replaces_rows and math.min(#lines, s.replaces_rows) or 1

    local virt_lines = vim
      .iter(lines)
      :skip(row_overlays)
      :map(function(l)
        return { { l, ghost.highlight_group } }
      end)
      :totable()

    for k, line_k in vim.iter(lines):take(row_overlays):enumerate() do
      coroutine.yield {
        row = anchor_row + k - 1,
        col = k == 1 and cursor_col or 0,
        opts = {
          virt_text = line_k ~= "" and {
            {
              line_k,
              ghost.highlight_group,
            },
          } or {},
          virt_text_pos = k == 1 and s.inline and "inline" or "overlay",
          hl_mode = "replace",
          virt_lines = k == row_overlays and #virt_lines > 0 and virt_lines or nil,
        },
      }
    end
  end)
end

local nvim_buf_set_extmark = errs.with_reporting(vim.api.nvim_buf_set_extmark)

---@param buf integer
---@param ghost config.GhostText
---@param s ghost.State
---@param line string
---@param cursor_col integer
local render = function(buf, ghost, s, line, cursor_col)
  clear_ns(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  for mark in M._extmarks(ghost, s, line, cursor_col) do
    if mark.row >= count then
      break
    end
    nvim_buf_set_extmark(buf, NS, mark.row, mark.col, mark.opts)
  end
end

---@param n async.Nursery
---@param settings config.Settings
---@param ev completions.Events
M.bind = function(n, settings, ev)
  local generation = 0

  vim.api.nvim_set_decoration_provider(NS, {
    on_win = function(_, _, buf)
      return state_of(buf) ~= nil
    end,
    on_line = function(_, win, buf, row)
      local s = state_of(buf)
      if s == nil or lsp_inline_active(buf) then
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

      if row >= vim.api.nvim_buf_line_count(buf) then
        return
      end
      local line = unpack(vim.api.nvim_buf_get_lines(buf, row, row + 1, true))
      render(buf, settings.display.ghost_text, s, line, col)
    end,
  })

  events.subscribe_latest(n, ev.leave, function(buf)
    atools.scheduled()
    M.clear(buf)
  end)

  ---@diagnostic disable-next-line: undefined-field
  events.subscribe_latest(n, ev.completion, function(pum_ev)
    ---@diagnostic disable-next-line: undefined-field
    local done = pum_ev.kind == "done" or pum_ev.kind == "clear"
    if not done and pum_ev.kind ~= "changed" then
      return
    end

    generation = generation + 1
    local ticket = generation
    vim.schedule(function()
      if ticket ~= generation or not vim.api.nvim_buf_is_valid(pum_ev.buf) then
        return
      end
      if done then
        M.clear(pum_ev.buf)
        return
      end
      if pum_ev.buf ~= vim.api.nvim_get_current_buf() then
        return
      end

      local ci = pum_ev.completed_item
      if type(ci) ~= "table" then
        return
      end

      if type(ci.user_data) == "table" and ci.user_data.word then
        M.show(context.full(), ci.user_data --[[@as completions.Item]])
      elseif ci.word and ci.word ~= "" then
        M.clear(pum_ev.buf)
      end
    end)
  end)
end

return M
