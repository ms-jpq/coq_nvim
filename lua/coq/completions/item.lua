local lsp_util = require "coq.producers.lsp.util"

---@class completions.ItemLspMeta
---@field client_id? integer
---@field client_name? string
---@field item? lsp.CompletionItem
---@field position_encoding? string

---@class completions.ItemDoc
---@field lines string[]
---@field filetype string

---@class completions.ItemMeta
---@field uid string
---@field source string
---@field filter string
---@field fuzzy number
---@field always_on_top? boolean
---@field doc? completions.ItemDoc
---@field path? string
---@field lsp? completions.ItemLspMeta

---@class completions.Item: vim.v.completed_item
---@field meta completions.ItemMeta

local M = {}

---@param item completions.Item
---@return string
M.dedup_key = function(item)
  local meta = item.meta
  local snippet = lsp_util.snippet(meta.lsp and meta.lsp.item)
  if snippet then
    return "snip\0" .. snippet
  end
  local edit = meta.lsp and meta.lsp.item and meta.lsp.item.textEdit

  if edit then
    local range = edit.range or edit.replace
    if range then
      return string.format(
        "r\0%d:%d-%d:%d\0%s",
        range.start.line,
        range.start.character,
        range["end"].line,
        range["end"].character,
        edit.newText or ""
      )
    end
  end

  return "txt\0" .. (item.word or "")
end

-- https://github.com/ms-jpq/coq_nvim/blob/coq/coq/server/icons.py
---@param icons config.Icons
---@param kind string
---@return string display
---@return string? hl_group
local iconify = function(icons, kind)
  if kind == "" or icons.mode == "none" then
    return kind, icons.hl_groups[kind]
  end

  local resolved = icons.aliases[kind] or kind
  local glyph, hl = icons.mappings[resolved], icons.hl_groups[resolved]

  if not glyph then
    return kind, hl
  end

  if icons.mode == "short" then
    return glyph, hl
  end

  return glyph .. string.rep(" ", math.max(1, icons.spacing)) .. kind, hl
end

---@param icons config.Icons
---@param item completions.Item
---@return vim.v.completed_item
M.to_nvim = function(icons, item)
  local kind, hl = iconify(icons, item.kind)

  return {
    dup = 1,
    equal = 1,
    empty = 1,
    word = lsp_util.snippet(item.meta.lsp and item.meta.lsp.item) and item.abbr or item.word,
    abbr = item.abbr or item.word,
    abbr_hlgroup = item.abbr_hlgroup,
    menu = item.menu,
    info = item.info,
    kind = kind,
    kind_hlgroup = item.kind_hlgroup or hl,
    user_data = item,
  }
end

return M
