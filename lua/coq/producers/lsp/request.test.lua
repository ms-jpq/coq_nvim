local T = require "coq.lib.test"
local request = require "coq.producers.lsp.request"

local kinds = vim.lsp.protocol.CompletionTriggerKind

---@param overrides? table
---@return vim.lsp.Client
local client_of = function(overrides)
  local base = {
    id = 7,
    name = "fido",
    offset_encoding = "utf-16",
    server_capabilities = {
      completionProvider = { triggerCharacters = { ".", "->" } },
    },
  }
  return vim.tbl_deep_extend("force", base, overrides or {}) --[[@as vim.lsp.Client]]
end

---@param overrides? table
---@return ctx.full
local ctx_of = function(overrides)
  -- Use a fresh scratch buf each time so the incomplete buf-var doesn't leak.
  local buf = vim.api.nvim_create_buf(false, true)
  local base = {
    win = 0,
    buf = buf,
    pos = { 3, 8, 8, 8 }, -- row=3, byte=8, utf16=8, utf32=8
    line = "",
    line_before = "",
    changedtick = 0,
    filetype = "",
    manual = false,
    cwd = "",
    filename = "",
    linesep = "\n",
    iskeyword = {},
    isfname = "",
    wildignore = "",
    comment = { "", "" },
    keyword_before = "",
    keyword_before_has_upper = false,
    symbol_before = "",
  }
  return vim.tbl_deep_extend("force", base, overrides or {}) --[[@as ctx.full]]
end

local TD = { uri = "file:///tmp/spot.lua" } ---@type lsp.TextDocumentIdentifier

T.describe({ "lsp.request._params_of" }, function(test)
  test({ "Invoked when no trigger char and no incomplete-pending" }, function()
    local p = request._params_of(client_of(), ctx_of(), TD, nil, "tok-1")
    T.eq(p.context.triggerKind, kinds.Invoked)
    T.eq(p.context.triggerCharacter, nil)
    T.eq(p.partialResultToken, "tok-1")
    T.eq(p.textDocument, TD)
  end)

  test({ "TriggerCharacter when trigger char provided" }, function()
    local p = request._params_of(client_of(), ctx_of(), TD, ".", "tok-2")
    T.eq(p.context.triggerKind, kinds.TriggerCharacter)
    T.eq(p.context.triggerCharacter, ".")
  end)

  test({ "TriggerCharacter for multi-char triggers like ->" }, function()
    local p = request._params_of(client_of(), ctx_of(), TD, "->", "tok-3")
    T.eq(p.context.triggerKind, kinds.TriggerCharacter)
    T.eq(p.context.triggerCharacter, "->")
  end)

  test({ "TriggerForIncompleteCompletions when buf-var is set, no trigger char" }, function()
    local client = client_of()
    local ctx = ctx_of()
    vim.b[ctx.buf]["__coq_lsp_incomplete_" .. client.id] = true
    local p = request._params_of(client, ctx, TD, nil, "tok-4")
    T.eq(p.context.triggerKind, kinds.TriggerForIncompleteCompletions)
    T.eq(p.context.triggerCharacter, nil)
  end)

  test({ "TriggerCharacter wins over incomplete-pending" }, function()
    local client = client_of()
    local ctx = ctx_of()
    vim.b[ctx.buf]["__coq_lsp_incomplete_" .. client.id] = true
    local p = request._params_of(client, ctx, TD, ".", "tok-5")
    T.eq(p.context.triggerKind, kinds.TriggerCharacter)
    T.eq(p.context.triggerCharacter, ".")
  end)

  test({ "position.line is 0-based (row - 1)" }, function()
    local p = request._params_of(client_of(), ctx_of { pos = { 10, 0, 0, 0 } }, TD, nil, "t")
    T.eq(p.position.line, 9)
  end)

  test({ "position.character picks utf-16 index for utf-16 encoding" }, function()
    local p =
      request._params_of(client_of { offset_encoding = "utf-16" }, ctx_of { pos = { 1, 100, 50, 25 } }, TD, nil, "t")
    T.eq(p.position.character, 50)
  end)

  test({ "position.character picks utf-32 index for utf-32 encoding" }, function()
    local p =
      request._params_of(client_of { offset_encoding = "utf-32" }, ctx_of { pos = { 1, 100, 50, 25 } }, TD, nil, "t")
    T.eq(p.position.character, 25)
  end)

  test({ "position.character picks byte index for utf-8 encoding" }, function()
    local p =
      request._params_of(client_of { offset_encoding = "utf-8" }, ctx_of { pos = { 1, 100, 50, 25 } }, TD, nil, "t")
    T.eq(p.position.character, 100)
  end)
end)
