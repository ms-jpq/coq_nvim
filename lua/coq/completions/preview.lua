local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local context = require "coq.lib.context"
local lib = require "coq.lib"
local paths_util = require "coq.producers.paths.util"
local resolve = require "coq.completions.resolve"

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

---@param ctx ctx.base
---@param ghost config.GhostText
---@param i completions.Item
local show_ghost = function(ctx, ghost, i)
  if not ghost.enabled then
    return
  end

  local text = i.meta.snippet and i.abbr or i.word
  if not text or text == "" then
    return
  end

  local row, col = unpack(ctx.pos)
  local inline = ghost.context[1] .. text .. ghost.context[2]

  vim.api.nvim_buf_set_extmark(ctx.buf, NS, row - 1, col, {
    virt_text = { { inline, ghost.highlight_group } },
    virt_text_pos = "overlay",
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

---@param preview_cfg config.PreviewDisplay
---@param lines string[]
---@param filetype string
local show_ts_doc = function(preview_cfg, lines, filetype)
  if #lines == 0 then
    return
  end

  atools.scheduled()
  local _, win = vim.lsp.util.open_floating_preview(lines, filetype, {
    border = preview_cfg.border,
    focusable = false,
    max_width = preview_cfg.x_max_len,
    close_events = {},
  })
  preview_win = win
end

---@param ctx ctx.base
---@param settings config.Settings
---@param item completions.Item
local show_doc = function(ctx, settings, item)
  local preview_cfg = settings.display.preview
  if not preview_cfg.enabled then
    return
  end
  local meta = item.meta

  if meta.doc then
    return show_ts_doc(preview_cfg, meta.doc.lines, meta.doc.filetype)
  end

  if meta.path then
    local lines = vim
      .iter(paths_util.path_preview({
        max_lines = settings.clients.paths.preview_lines,
        ellipsis = settings.display.pum.ellipsis,
      }, vim.fn.getcwd(), meta.path))
      :totable()
    return show_ts_doc(preview_cfg, lines, "")
  end

  local lsp_item = meta.lsp and meta.lsp.item
  if lsp_item then
    if not lsp_item.documentation and not lsp_item.detail then
      resolve.enrich(ctx, item)
    end
    return show_ts_doc(preview_cfg, md_lines(lsp_item), "markdown")
  end
end

---@param ev completions.PumEvent
---@return completions.Item?
local item_of = function(ev)
  if ev.kind ~= "changed" then
    return nil
  end

  local item = ev.item and ev.item.user_data
  return type(item) == "table" and item.word and item or nil
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
        local item = item_of(ev)

        if item then
          show_ghost(ctx, settings.display.ghost_text, item)
          show_doc(ctx, settings, item)
        end
      end)
    end
  end)
end

return M
