---@class index.RowMeta
---@field filter? string
---@field snippet? string

---@class index.Row
---@field word string
---@field abbr? string
---@field abbr_hlgroup? string
---@field menu? string
---@field info? string
---@field kind? string
---@field kind_hlgroup? string
---@field meta index.RowMeta

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

---@param row index.Row
---@return table
M.to_item = function(row)
  return {
    dup = 1,
    equal = 1,
    empty = 1,
    word = row.meta.snippet and row.abbr or row.word,
    abbr = row.abbr,
    abbr_hlgroup = row.abbr_hlgroup,
    menu = row.menu,
    info = row.info,
    kind = row.kind,
    kind_hlgroup = row.kind_hlgroup or kind_hl[row.kind],
    user_data = row,
  }
end

return M
