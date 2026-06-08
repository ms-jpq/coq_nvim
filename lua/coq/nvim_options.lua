local COMPLETEFUNC = "coq_completefunc"

local M = {}

M.CE = vim.keycode [[<c-e>]]

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

---@param keymap config.KeyMapping
local recommended_keymaps = function(keymap)
  if not keymap.recommended then
    return
  end
  local expr = { noremap = true, expr = true }

  for _, key in pairs { "<esc>", "<c-c>", "<bs>", "<c-w>", "<c-u>" } do
    vim.keymap.set({ "i" }, key, function()
      return (vim.fn.pumvisible() == 1 and M.CE or "") .. key
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
local manual_complete = function(keymap)
  if not keymap.manual_complete then
    return
  end

  vim.keymap.set({ "i" }, keymap.manual_complete, function()
    if vim.fn.pumvisible() ~= 0 then
      return [[<c-e><c-x><c-u>]]
    end
    return [[<c-x><c-u>]]
  end, { noremap = true, expr = true })

  if not keymap.manual_complete_insertion_only then
    vim.keymap.set({ "n", "v" }, keymap.manual_complete, [[<c-\><c-n>i<c-x><c-u>]], { noremap = true })
  end
end

---@param events completions.Events
local complete_func = function(events)
  _G[COMPLETEFUNC] = function(findstart, _)
    if findstart == 1 then
      events.trigger.replace { manual = true }
      return -1
    end
    return {}
  end
  vim.o.completefunc = "v:lua." .. COMPLETEFUNC
end

---@param settings config.Settings
---@param events completions.Events
M.apply = function(settings, events)
  completeopt(settings.keymap)
  recommended_keymaps(settings.keymap)
  manual_complete(settings.keymap)
  complete_func(events)
end

return M
