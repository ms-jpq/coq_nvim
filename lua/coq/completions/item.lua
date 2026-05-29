---@class completions.ItemLspMeta
---@field client_id? integer
---@field item? lsp.CompletionItem
---@field additional_text_edits? lsp.TextEdit[]
---@field position_encoding? string
---@field command? lsp.Command

---@class completions.ItemMeta
---@field filter? string
---@field snippet? string
---@field lsp? completions.ItemLspMeta

---@class completions.Item: vim.v.completed_item
---@field meta completions.ItemMeta

local M = {}

local kind_hl = {
  Class = "@type",
  Constant = "@constant",
  Constructor = "@constructor",
  Enum = "@type",
  EnumMember = "@constant",
  Event = "@type",
  Field = "@variable.member",
  File = "Directory",
  Folder = "Directory",
  Function = "@function",
  Interface = "@type",
  Keyword = "@keyword",
  Method = "@function.method",
  Module = "@module",
  Operator = "@operator",
  Property = "@property",
  Reference = "@string.special",
  Snippet = "@string.special",
  Struct = "@type",
  Text = "@string",
  TypeParameter = "@type.qualifier",
  Unit = "@constant",
  Value = "@constant",
  Variable = "@variable",
}

---@param item completions.Item
---@return vim.v.completed_item
M.to_nvim = function(item)
  return {
    dup = 1,
    equal = 1,
    empty = 1,
    word = item.meta.snippet and item.abbr or item.word,
    abbr = item.abbr,
    abbr_hlgroup = item.abbr_hlgroup,
    menu = item.menu,
    info = item.info,
    kind = item.kind,
    kind_hlgroup = item.kind_hlgroup or kind_hl[item.kind],
    user_data = item,
  }
end

return M
