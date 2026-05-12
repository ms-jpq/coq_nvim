#!/usr/bin/env -S -- nvim -l

for _, f in ipairs(vim.fn.globpath("lua", "**/*.test.lua", false, true)) do
  vim.notify([[🧪 ]] .. f, vim.log.levels.INFO)
  vim.cmd("source " .. vim.fn.fnameescape(f))
end
