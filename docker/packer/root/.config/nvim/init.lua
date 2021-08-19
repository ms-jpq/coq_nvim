require("packer").startup(
  function(use)
    use {"neovim/nvim-lspconfig"}
    use {"ms-jpq/coq_nvim", branch = "pr-53"}
    use {"ms-jpq/coq.artifacts"}
  end
)

local lsp = require "lspconfig"
local coq = require("coq")
lsp.cssls.setup(coq.lsp_ensure_capabilities())
