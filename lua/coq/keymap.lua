local CE = vim.keycode [[<c-e>]]

local function has_text_before_cursor()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before_cursor = string.sub(line, 1, col)
  return string.match(before_cursor, "%S") ~= nil
end

local M = {}

---@param mapping config.KeyMapping
M.apply = function(mapping)
  local opts = { noremap = true, expr = true }

  if mapping.recommended then
    for _, key in pairs { "<esc>", "<c-c>", "<bs>", "<c-w>", "<c-u>" } do
      vim.keymap.set("i", key, function()
        return (vim.fn.pumvisible() == 1 and CE or "") .. key
      end, opts)
    end

    vim.keymap.set({ "i", "s" }, "<cr>", function()
      if vim.fn.pumvisible() == 0 then
        return [[<cr>]]
      end
      if vim.fn.complete_info({ "selected" }).selected == -1 then
        return [[<c-e><cr>]]
      end
      return [[<c-y>]]
    end, opts)

    vim.keymap.set({ "i", "s" }, "<tab>", function()
      if vim.fn.pumvisible() ~= 0 and has_text_before_cursor() then
        return [[<c-n>]]
      end
      return [[<tab>]]
    end, opts)

    vim.keymap.set({ "i", "s" }, "<s-tab>", function()
      if vim.fn.pumvisible() ~= 0 and has_text_before_cursor() then
        return [[<c-p>]]
      end
      return [[<bs>]]
    end, opts)
  end

  if mapping.manual_complete then
    vim.keymap.set("i", mapping.manual_complete, function()
      if vim.fn.pumvisible() ~= 0 then
        return [[<c-e><c-x><c-u>]]
      end

      return [[<c-x><c-u>]]
    end, opts)
  end
end

return M
