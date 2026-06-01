local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local lib = require "coq.lib"
local lsp_util = require "coq.producers.lsp.util"
local paths_util = require "coq.producers.paths.util"

local NS = vim.api.nvim_create_namespace "coq.preview"

local preview_win = nil

local close_preview = function()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  preview_win = nil
end

---@param buf integer
local clear = function(buf)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  close_preview()
end

---@param i completions.Item
---@return string
local insertion_text = function(i)
  if i.meta.snippet then
    return i.meta.snippet
  end
  local lsp_item = i.meta.lsp and i.meta.lsp.item
  if lsp_item and lsp_item.textEdit and lsp_item.textEdit.newText then
    return lsp_item.textEdit.newText
  end
  return i.word or ""
end

---@param ctx ctx.base
---@param ghost config.GhostText
---@param i completions.Item
local show_ghost = function(ctx, ghost, i)
  if not ghost.enabled then
    return
  end

  local text = insertion_text(i)
  if text == "" then
    return
  end

  local row, col = unpack(ctx.pos)
  local lhs, rhs = unpack(ghost.context)

  local lines = vim.split(text, "\n", { plain = true })
  local first = lhs .. lines[1] .. (#lines == 1 and rhs or "")
  local rest = vim
    .iter(async.wrap(function()
      for k = 2, #lines do
        local content = lines[k] .. (k == #lines and rhs or "")
        coroutine.yield { { content, ghost.highlight_group } }
      end
    end))
    :totable()

  vim.api.nvim_buf_set_extmark(ctx.buf, NS, row - 1, col, {
    virt_text = { { first, ghost.highlight_group } },
    virt_text_pos = "overlay",
    virt_lines = #rest > 0 and rest or nil,
    hl_mode = "combine",
  })
end

---@param lsp_item lsp.CompletionItem
---@return string[]
local md_lines = function(lsp_item)
  return vim
    .iter(async.wrap(function()
      if lsp_item.detail and lsp_item.detail ~= "" then
        for line in lib.splitlines(lsp_item.detail) do
          coroutine.yield(line)
        end
      end

      if lsp_item.documentation then
        for _, line in ipairs(vim.lsp.util.convert_input_to_markdown_lines(lsp_item.documentation)) do
          coroutine.yield(line)
        end
      end
    end))
    :totable()
end

---@class preview.Pos
---@field row integer
---@field col integer
---@field width integer
---@field height integer

---@param border any
---@return integer w
---@return integer h
local border_w_h = function(border)
  if border == nil or border == "" or border == "none" then
    return 0, 0
  end
  return 1, 1
end

---@param preview_cfg config.PreviewDisplay
---@param ev completions.PumChangedEvent
---@param lines string[]
---@return preview.Pos?
local pick_position = function(preview_cfg, ev, lines)
  local scr_w, scr_h = vim.o.columns, vim.o.lines
  local top, btm = ev.row, ev.row + ev.height + 1
  local left = ev.col
  local right = ev.col + ev.width + (ev.scrollbar and 1 or 0)

  local max_w, cap_h = 0, 0
  for _, line in ipairs(lines) do
    local w = math.max(1, vim.fn.strdisplaywidth(line))
    max_w = math.max(max_w, w)
    cap_h = cap_h + math.ceil(w / preview_cfg.x_max_len)
  end
  local cap_w = math.min(preview_cfg.x_max_len, max_w)
  cap_h = math.max(1, cap_h)

  local b_w, b_h = border_w_h(preview_cfg.border)
  local ns_w = lib.clamp(1, scr_w - left, cap_w)
  local we_h = lib.clamp(1, scr_h - top - 2, cap_h)
  local p = preview_cfg.positions

  ---@type { rank: integer, idx: integer, pos: preview.Pos }[]
  local cs = {}

  local n_h = lib.clamp(1, top - 1, cap_h)
  if p.north and (top - 1 - n_h - b_h) > 1 then
    cs[#cs + 1] =
      { rank = p.north, idx = 1, pos = { row = top - 1 - n_h - b_h, col = left - 1, height = n_h, width = ns_w } }
  end

  local s_h = lib.clamp(1, scr_h - btm, cap_h)
  if p.south and (btm + s_h) < scr_h - 1 then
    cs[#cs + 1] = { rank = p.south, idx = 2, pos = { row = btm, col = left - 1, height = s_h, width = ns_w } }
  end

  if p.west then
    local w_w = lib.clamp(1, left - 2, cap_w)
    cs[#cs + 1] =
      { rank = p.west, idx = 3, pos = { row = top, col = left - 2 - w_w - b_w, height = we_h, width = w_w } }
  end

  if p.east then
    cs[#cs + 1] = {
      rank = p.east,
      idx = 4,
      pos = { row = top, col = right + 1, height = we_h, width = lib.clamp(1, scr_w - right - 2, cap_w) },
    }
  end

  if #cs == 0 then
    return nil
  end

  table.sort(cs, function(a, b)
    local area_a, area_b = a.pos.height * a.pos.width, b.pos.height * b.pos.width
    if area_a ~= area_b then
      return area_a > area_b
    end
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.idx < b.idx
  end)

  return cs[1].pos
end

---@param preview_cfg config.PreviewDisplay
---@param ev completions.PumChangedEvent
---@param lines string[]
---@param filetype string
local show_ts_doc = function(preview_cfg, ev, lines, filetype)
  if #lines == 0 then
    return
  end

  atools.scheduled()
  local pos = pick_position(preview_cfg, ev, lines)
  if not pos then
    return
  end

  local _, win = vim.lsp.util.open_floating_preview(lines, filetype, {
    border = preview_cfg.border,
    focusable = false,
    max_width = preview_cfg.x_max_len,
    close_events = {},
  })

  vim.api.nvim_win_set_config(win, {
    relative = "editor",
    anchor = "NW",
    row = pos.row,
    col = pos.col,
    width = pos.width,
    height = pos.height,
    border = preview_cfg.border,
  })

  preview_win = win
end

---@param ctx ctx.base
---@param settings config.Settings
---@param item completions.Item
---@return string[]? lines
---@return string filetype
local resolve_doc = function(ctx, settings, item)
  local meta = item.meta

  if meta.doc then
    return meta.doc.lines, meta.doc.filetype
  end

  if meta.path then
    return vim
      .iter(paths_util.path_preview({
        max_lines = settings.clients.paths.preview_lines,
        ellipsis = settings.display.pum.ellipsis,
      }, vim.fn.getcwd(), meta.path))
      :totable(),
      ""
  end

  local lsp_item = meta.lsp and meta.lsp.item
  if lsp_item then
    if not lsp_item.documentation and not lsp_item.detail then
      lsp_util.enrich(ctx, item)
    end
    return md_lines(lsp_item), "markdown"
  end

  return nil, ""
end

---@param ctx ctx.base
---@param settings config.Settings
---@param ev completions.PumChangedEvent
---@param item completions.Item
local show_doc = function(ctx, settings, ev, item)
  if not settings.display.preview.enabled then
    return
  end
  local lines, filetype = resolve_doc(ctx, settings, item)
  if lines then
    show_ts_doc(settings.display.preview, ev, lines, filetype)
  end
end

---@param ev completions.PumEvent
---@return completions.PumChangedEvent?
---@return completions.Item?
local item_of = function(ev)
  if ev.kind ~= "changed" then
    return nil, nil
  end
  ---@cast ev completions.PumChangedEvent

  local item = ev.completed_item and ev.completed_item.user_data
  if type(item) ~= "table" or not item.word then
    return nil, nil
  end
  ---@cast item completions.Item
  return ev, item
end

---@param buf integer
local promote = function(buf)
  local ft = vim.bo[buf].filetype
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)

  vim.cmd "silent! pedit COQ-preview"
  vim.cmd "wincmd P"

  local new_buf = vim.api.nvim_get_current_buf()
  do
    vim.bo[new_buf].buftype = "nofile"
    vim.bo[new_buf].bufhidden = "wipe"
    vim.bo[new_buf].swapfile = false
  end

  vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)
  if ft ~= "" then
    vim.bo[new_buf].filetype = ft
  end
  vim.cmd "wincmd p"
end

local M = {}

---@param n async.Nursery
---@param settings config.Settings
---@param pum channels.Broadcast<completions.PumEvent>
M.bind = function(n, settings, pum)
  if settings.keymap.bigger_preview then
    local esc = vim.keycode "<c-e>"
    vim.keymap.set({ "i" }, settings.keymap.bigger_preview, function()
      if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
        return settings.keymap.bigger_preview
      end
      local buf = vim.api.nvim_win_get_buf(preview_win)

      n.spawn(function()
        atools.scheduled()
        close_preview()
        promote(buf)
      end)

      return esc
    end, { expr = true, noremap = true })
  end

  n.spawn(function(defer)
    local iter = pum.subscribe()
    defer(iter.close)

    for ev in iter do
      n.spawn(function()
        local ctx = context.base()
        clear(ctx.buf)
        local changed_ev, item = item_of(ev)
        if item then
          show_ghost(ctx, settings.display.ghost_text, item)
          if changed_ev then
            show_doc(ctx, settings, changed_ev, item)
          end
        end
      end)
    end
  end)
end

return M
