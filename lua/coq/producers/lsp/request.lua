local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local lsp_util = require "coq.producers.lsp.util"
local util = require "coq.producers.util"

---@class lsp.RequestItem
---@field client_id integer
---@field client_name string
---@field offset_encoding string
---@field kind string
---@field item lsp.CompletionItem

local M = {}

local INCOMPLETE_VAR_PREFIX = "__coq_lsp_incomplete_"

---@type fun(): integer
local next_token_id = (function()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end)()

---@param line string
---@param col integer
---@param offset_encoding string
---@return integer
local encode_col = function(line, col, offset_encoding)
  if offset_encoding == "utf-16" then
    return vim.str_utfindex(line, "utf-16", col, true)
  elseif offset_encoding == "utf-32" then
    return vim.str_utfindex(line, "utf-32", col, true)
  end
  return col
end

---@param value lsp.CompletionList|lsp.CompletionItem[]|nil
---@return lsp.CompletionItem[]
local items_of = function(value)
  if type(value) ~= "table" then
    return {}
  end
  if value.items then
    return value.items --[[@as lsp.CompletionItem[] ]]
  end
  return value --[[@as lsp.CompletionItem[] ]]
end

---@param client vim.lsp.Client
---@param ctx ctx.full
---@param td_params lsp.TextDocumentIdentifier
---@return fun() close
---@return lib.Iterator<lsp.CompletionItem> iter
local query_one = function(client, ctx, td_params)
  return closable.iter(function(defer)
    atools.scheduled()
    local token = "coq.lsp." .. client.id .. "." .. next_token_id()
    local kinds = vim.lsp.protocol.CompletionTriggerKind
    local incomplete_var = INCOMPLETE_VAR_PREFIX .. client.id
    local trigger_kind = vim.b[ctx.buf][incomplete_var] and kinds.TriggerForIncompleteCompletions or kinds.Invoked

    local row, col = unpack(ctx.pos)
    local params = {
      position = {
        line = row - 1,
        character = encode_col(ctx.line, col, client.offset_encoding),
      },
      textDocument = td_params,
      context = { triggerKind = trigger_kind },
      partialResultToken = token,
    } --[[@as lsp.CompletionParams]]

    ---@type lsp.CompletionItem[]
    local partial = {}
    local autocmd_id = vim.api.nvim_create_autocmd("LspProgress", {
      callback = function(args)
        if args.data and args.data.client_id == client.id and args.data.params and args.data.params.token == token then
          for _, item in ipairs(items_of(args.data.params.value)) do
            table.insert(partial, item)
          end
        end
      end,
    })
    defer(function()
      pcall(vim.api.nvim_del_autocmd, autocmd_id)
    end)

    local err, result = lsp_util.request(client, "textDocument/completion", params, ctx.buf)

    for _, item in pairs(partial) do
      coroutine.yield(item)
    end

    if not err and result then
      local incomplete = type(result) == "table" and result.isIncomplete == true
      if vim.api.nvim_buf_is_valid(ctx.buf) then
        vim.b[ctx.buf][incomplete_var] = incomplete or nil
      end
      for _, item in pairs(items_of(result)) do
        coroutine.yield(item)
      end
    end
  end)
end

---@param ignored lib.Set<string>
---@param ctx ctx.full
---@return fun() close
---@return lib.Iterator<lsp.RequestItem[]> iter
M.query = function(ignored, ctx)
  return closable.iter(function(defer)
    if not util.is_live(ctx.buf) then
      return
    end

    local clients = vim.tbl_filter(function(c)
      return not ignored[c.name]
    end, vim.lsp.get_clients { bufnr = ctx.buf, method = "textDocument/completion" })
    if #clients == 0 then
      return
    end

    local td_params = vim.lsp.util.make_text_document_params(ctx.buf)
    local batchers = vim
      .iter(clients)
      :map(function(client)
        return async.wrap(function()
          local close, items = query_one(client, ctx, td_params)
          defer(close)

          local batch = vim
            .iter(items)
            :map(function(item)
              return {
                client_id = client.id,
                client_name = client.name,
                offset_encoding = client.offset_encoding,
                kind = vim.lsp.protocol.CompletionItemKind[item.kind] or "",
                item = item,
              }
            end)
            :totable()
          if #batch > 0 then
            coroutine.yield(batch)
          end
        end)
      end)
      :totable()

    local close, merged = async.merge(batchers)
    defer(close)

    for _, batch in merged do
      coroutine.yield(batch)
    end
  end)
end

return M
