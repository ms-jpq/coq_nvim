#!/usr/bin/env -S -- nvim -l

local rock_dir = assert(vim.env.ROCK_DIR)

vim.opt.rtp:append { rock_dir }
vim.cmd.filetype "plugin on"
vim.cmd.syntax "enable"
vim.cmd.runtime { "ftdetect/*.vim", bang = true }
vim.cmd.edit "sample.snip"

assert(vim.bo.filetype == "coq-snip")
assert(vim.bo.commentstring == "# %s")
assert(vim.fn.hlexists "csTrailingWS" == 1)

require("coq").setup()
