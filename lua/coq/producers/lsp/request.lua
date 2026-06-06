local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local buffers = require "coq.lib.buffers"
local closable = require "coq.lib.closable"
local lsp_util = require "coq.producers.lsp.util"
local mpmc = require "coq.lib.channels.mpmc"

---@class lsp.RequestItem
---@field client_id integer
---@field client_name string
---@field offset_encoding string
---@field kind string
---@field item lsp.CompletionItem

local M = {}

---@type fun(): integer
local next_token_id = (function()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end)()

---@param pos [integer, integer, integer, integer]
---@param offset_encoding string
---@return integer
local col_for = function(pos, offset_encoding)
  local _, b, u16, u32 = unpack(pos)
  if offset_encoding == "utf-16" then
    return u16
  elseif offset_encoding == "utf-32" then
    return u32
  end
  return b
end

local kinds = vim.lsp.protocol.CompletionTriggerKind

---@param client_id integer
---@return string
local incomplete_var_of = function(client_id)
  return "__coq_lsp_incomplete_" .. client_id
end

---@param client vim.lsp.Client
---@param ctx ctx.full
---@return string?
local trigger_char_of = function(client, ctx)
  local cap = client.server_capabilities
  local triggers = cap and cap.completionProvider and cap.completionProvider.triggerCharacters

  if not triggers then
    return nil
  end
  for _, t in pairs(triggers) do
    if t ~= "" and vim.endswith(ctx.line_before, t) then
      return t
    end
  end
  return nil
end

---@param buf integer
---@param client_id integer
---@param trigger_char string?
---@return integer
local trigger_kind_of = function(buf, client_id, trigger_char)
  if trigger_char then
    return kinds.TriggerCharacter
  end
  if vim.b[buf][incomplete_var_of(client_id)] then
    return kinds.TriggerForIncompleteCompletions
  end
  return kinds.Invoked
end

---@param client vim.lsp.Client
---@param ctx ctx.full
---@param td_params lsp.TextDocumentIdentifier
---@return fun() close
---@return lib.Iterator<lsp.CompletionItem[]> iter
local query_1 = function(client, ctx, td_params)
  return closable.iter(function(defer)
    atools.scheduled()

    local token = "coq.lsp." .. client.id .. "." .. next_token_id()
    local trigger_char = trigger_char_of(client, ctx)
    local incomplete = false

    ---@param value lsp.CompletionList|lsp.CompletionItem[]|nil
    ---@return lsp.CompletionItem[]
    local items_of = function(value)
      if type(value) ~= "table" then
        return {}
      end
      incomplete = incomplete or value.isIncomplete == true
      return value.items or value
    end

    defer(function()
      atools.scheduled()
      if vim.api.nvim_buf_is_valid(ctx.buf) then
        vim.b[ctx.buf][incomplete_var_of(client.id)] = incomplete or nil
      end
    end)

    local row = ctx.pos[1]
    local params = {
      position = { line = row - 1, character = col_for(ctx.pos, client.offset_encoding) },
      textDocument = td_params,
      context = {
        triggerKind = trigger_kind_of(ctx.buf, client.id, trigger_char),
        triggerCharacter = trigger_char,
      },
      partialResultToken = token,
    }

    ---@type channels.Mpmc<lsp.CompletionItem[]>
    local chan = mpmc.new(math.huge)
    defer(chan.close)

    -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#partialResults
    local group = vim.api.nvim_create_augroup("coq.lsp.progress." .. client.name, { clear = true })
    local autocmd_id = vim.api.nvim_create_autocmd("LspProgress", {
      group = group,
      callback = function(args)
        if args.data.client_id == client.id and args.data.params.token == token then
          chan.push(items_of(args.data.params.value))
        end
      end,
    })
    defer(function()
      atools.scheduled()
      vim.api.nvim_del_autocmd(autocmd_id)
    end)

    local final = async.wrap(function()
      local err, result = lsp_util.request(client, "textDocument/completion", params, ctx.buf)
      chan.close()
      if err or not result then
        return
      end
      coroutine.yield(items_of(result))
    end)

    local close, merged = async.merge { chan.pull, final }
    defer(close)

    for _, batch in merged do
      coroutine.yield(batch)
    end
  end)
end

---@param ignored lib.Set<string>
---@param ctx ctx.full
---@return fun() close
---@return lib.Iterator<lsp.RequestItem[]> iter
M.query = function(ignored, ctx)
  return closable.iter(function(defer)
    if not buffers.is_live(ctx.buf) then
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
          local close, batches = query_1(client, ctx, td_params)
          defer(close)

          for batch in batches do
            local acc = vim
              .iter(batch)
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

            coroutine.yield(acc)
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
