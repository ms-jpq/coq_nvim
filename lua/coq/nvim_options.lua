local CE = vim.keycode [[<c-e>]]

local function has_text_before_cursor()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before_cursor = string.sub(line, 1, col)
  return string.match(before_cursor, "%S") ~= nil
end

---@param keymap config.KeyMapping
local completeopt = function(keymap)
  local copt = { "noinsert", "menuone" }
  if not keymap.pre_select then
    table.insert(copt, "noselect")
  end
  vim.opt.completeopt:append(copt)
end

---@param pum config.PumDisplay
local shortmess = function(pum)
  if pum.fast_close then
    vim.opt.shortmess:append "c"
  end
end

---@param keymap config.KeyMapping
local recommended_keymaps = function(keymap)
  if not keymap.recommended then
    return
  end
  local expr = { noremap = true, expr = true }

  for _, key in pairs { "<esc>", "<c-c>", "<bs>", "<c-w>", "<c-u>" } do
    vim.keymap.set("i", key, function()
      return (vim.fn.pumvisible() == 1 and CE or "") .. key
    end, expr)
  end

  vim.keymap.set({ "i", "s" }, "<cr>", function()
    if vim.fn.pumvisible() == 0 then
      return [[<cr>]]
    end
    if vim.fn.complete_info({ "selected" }).selected == -1 then
      return [[<c-e><cr>]]
    end
    return [[<c-y>]]
  end, expr)

  vim.keymap.set({ "i", "s" }, "<tab>", function()
    if vim.fn.pumvisible() ~= 0 and has_text_before_cursor() then
      return [[<c-n>]]
    end
    return [[<tab>]]
  end, expr)

  vim.keymap.set({ "i", "s" }, "<s-tab>", function()
    if vim.fn.pumvisible() ~= 0 and has_text_before_cursor() then
      return [[<c-p>]]
    end
    return [[<bs>]]
  end, expr)
end

---@param keymap config.KeyMapping
local jump_to_mark = function(keymap)
  if not keymap.jump_to_mark then
    return
  end
  vim.keymap.set({ "i", "s" }, keymap.jump_to_mark, function()
    if vim.snippet.active { direction = 1 } then
      return [[<cmd>lua vim.snippet.jump(1)<cr>]]
    end
    return keymap.jump_to_mark
  end, { noremap = true, expr = true })
end

---@param keymap config.KeyMapping
local manual_complete = function(keymap)
  if not keymap.manual_complete then
    return
  end

  vim.keymap.set("i", keymap.manual_complete, function()
    if vim.fn.pumvisible() ~= 0 then
      return [[<c-e><c-x><c-u>]]
    end
    return [[<c-x><c-u>]]
  end, { noremap = true, expr = true })

  if not keymap.manual_complete_insertion_only then
    vim.keymap.set({ "n", "v" }, keymap.manual_complete, [[<c-\><c-n>i<c-x><c-u>]], { noremap = true })
  end
end

local M = {}

---@param settings config.Settings
M.apply = function(settings)
  completeopt(settings.keymap)
  shortmess(settings.display.pum)
  recommended_keymaps(settings.keymap)
  manual_complete(settings.keymap)
  jump_to_mark(settings.keymap)
end

return M
