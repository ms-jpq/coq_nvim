local atools = require "coq.lib.atools"
local lib = require "coq.lib"
local paths_preview = require "coq.producers.paths.preview"
local txt = require "coq.lib.text"

local PREVIEW_VAR = "__coq_preview__"

---@param lsp_item lsp.CompletionItem
---@return string[]
local md_lines = function(lsp_item)
  return vim
    .iter(coroutine.wrap(function()
      if lsp_item.detail and lsp_item.detail ~= "" then
        for line in txt.splitlines(lsp_item.detail) do
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
  local pum_n = ev.row
  local pum_s = pum_n + ev.height - 1
  local pum_w = ev.col
  local pum_e = ev.col + ev.width + (ev.scrollbar and 1 or 0) - 1

  local max_w, cap_h = 0, 0
  for _, line in ipairs(lines) do
    local w = math.max(1, vim.fn.strdisplaywidth(line))
    max_w = math.max(max_w, w)
    cap_h = cap_h + math.ceil(w / preview_cfg.x_max_len)
  end
  local cap_w = math.min(preview_cfg.x_max_len, max_w)
  cap_h = math.max(1, cap_h)

  local b_w, b_h = border_w_h(preview_cfg.border)
  local ns_w = lib.clamp(1, scr_w - pum_w - 2 * b_w, cap_w)
  local we_h = lib.clamp(1, scr_h - pum_n - 1 - 2 * b_h, cap_h)
  local p = preview_cfg.positions

  ---@type { rank: integer, idx: integer, pos: preview.Pos }[]
  local cs = {}

  local n_h = lib.clamp(1, pum_n - 1 - 2 * b_h, cap_h)
  local n_row = pum_n - 1 - n_h - 2 * b_h
  if p.north and n_row >= 0 then
    cs[#cs + 1] = {
      rank = p.north,
      idx = 1,
      pos = { row = n_row, col = pum_w - 1, height = n_h, width = ns_w },
    }
  end

  local s_row = pum_s + 2
  local s_h = lib.clamp(1, scr_h - 1 - s_row - 2 * b_h, cap_h)
  if p.south and s_row + s_h - 1 + 2 * b_h <= scr_h - 1 then
    cs[#cs + 1] = {
      rank = p.south,
      idx = 2,
      pos = { row = s_row, col = pum_w - 1, height = s_h, width = ns_w },
    }
  end

  local w_w = lib.clamp(1, pum_w - 1 - 2 * b_w, cap_w)
  local w_col = pum_w - 1 - w_w - 2 * b_w
  if p.west and w_col >= 0 then
    cs[#cs + 1] = {
      rank = p.west,
      idx = 3,
      pos = { row = pum_n, col = w_col, height = we_h, width = w_w },
    }
  end

  local e_col = pum_e + 2
  local e_w = lib.clamp(1, scr_w - e_col - 2 * b_w, cap_w)
  if p.east and e_col + e_w - 1 + 2 * b_w <= scr_w - 1 then
    cs[#cs + 1] = {
      rank = p.east,
      idx = 4,
      pos = { row = pum_n, col = e_col, height = we_h, width = e_w },
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
local show = function(preview_cfg, ev, lines, filetype)
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

  vim.w[win][PREVIEW_VAR] = true
end

---@param item completions.Item
---@return string?
local multiline_insert = function(item)
  local meta = item.meta
  local text = meta.snippet
    or (meta.lsp and meta.lsp.item and meta.lsp.item.textEdit and meta.lsp.item.textEdit.newText)
    or item.word

  if text and txt.is_multiline(text) then
    return text
  end
  return nil
end

---@param ctx ctx.base
---@param settings config.Settings
---@param resolver completions.Resolver
---@param item completions.Item
---@return string[]? lines
---@return string filetype
local resolve_doc = function(ctx, settings, resolver, item)
  local meta = item.meta

  local doc_lines = meta.doc and meta.doc.lines or nil
  if doc_lines and #doc_lines > 0 then
    return doc_lines, meta.doc.filetype
  end

  if meta.path then
    return vim
      .iter(paths_preview.lines({
        max_lines = settings.clients.paths.preview_lines,
        ellipsis = settings.display.pum.ellipsis,
      }, vim.fn.getcwd(), meta.path))
      :totable(),
      ""
  end

  if meta.lsp then
    local lsp_item = meta.lsp.item
    if lsp_item and not lsp_item.documentation and not lsp_item.detail then
      local timeout_ms = math.floor(settings.display.preview.resolve_timeout * 1000)
      local lsp = resolver.resolve(ctx, item, timeout_ms)
      lsp_item = lsp and lsp.item
    end
    if lsp_item then
      local md = md_lines(lsp_item)
      if #md > 0 then
        return md, "markdown"
      end
    end
  end

  local multi = multiline_insert(item)
  if multi then
    atools.scheduled()
    return vim.iter(txt.splitlines(multi)):totable(), vim.bo[ctx.buf].filetype
  end

  return nil, ""
end

local M = {}

M.close = function()
  for _, win in pairs(vim.api.nvim_list_wins()) do
    if vim.w[win][PREVIEW_VAR] then
      vim.api.nvim_win_close(win, true)
    end
  end
end

---@return integer?
M.active_buf = function()
  for _, win in pairs(vim.api.nvim_list_wins()) do
    if vim.w[win][PREVIEW_VAR] then
      return vim.api.nvim_win_get_buf(win)
    end
  end
  return nil
end

---@param buf integer
M.promote = function(buf)
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

---@param ctx ctx.base
---@param settings config.Settings
---@param resolver completions.Resolver
---@param ev completions.PumChangedEvent
---@param item completions.Item
M.show = function(ctx, settings, resolver, ev, item)
  if not settings.display.preview.enabled then
    return
  end
  local lines, filetype = resolve_doc(ctx, settings, resolver, item)
  if lines then
    show(settings.display.preview, ev, lines, filetype)
  end
end

return M
