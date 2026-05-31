---@class completions.ItemLspMeta
---@field client_id? integer
---@field item? lsp.CompletionItem
---@field additional_text_edits? lsp.TextEdit[]
---@field position_encoding? string
---@field command? lsp.Command

---@class completions.ItemMeta
---@field filter? string
---@field snippet? string
---@field source? string
---@field always_on_top? boolean
---@field lsp? completions.ItemLspMeta

---@class completions.Item: vim.v.completed_item
---@field meta completions.ItemMeta

local M = {}

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
    word = item.meta.snippet and item.abbr or item.word,
    abbr = item.abbr,
    abbr_hlgroup = item.abbr_hlgroup,
    menu = item.menu,
    info = item.info,
    kind = kind,
    kind_hlgroup = item.kind_hlgroup or hl,
    user_data = item,
  }
end

return M
