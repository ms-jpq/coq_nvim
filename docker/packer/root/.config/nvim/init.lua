require("packer").startup(function(use)
  use { "neovim/nvim-lspconfig" }
  use { "ms-jpq/coq_nvim" }
  use { "ms-jpq/coq.artifacts" }
end)

local coq = require "coq"
local lsp = require "lspconfig"
lsp.cssls.setup(coq.lsp_ensure_capabilities())
lsp.cssls.setup(coq().lsp_ensure_capabilities())
assert(coq == coq()())
