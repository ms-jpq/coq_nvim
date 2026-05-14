#!/usr/bin/env -S -- nvim -l

do
  if os.getenv "TEST_JIT_OFF" then
    jit.off()
  end
  local lvl = tonumber(os.getenv "TEST_JIT_OPT")
  if lvl then
    jit.opt.start(lvl)
  end
end

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local T = require "coq.lib.test"

for _, f in ipairs(vim.fn.globpath("lua", "**/*.test.lua", false, true)) do
  vim.cmd("source " .. vim.fn.fnameescape(f))
end

T.run(tonumber(os.getenv "TEST_SEED"))
