local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local closable = require "coq.lib.closable"
local lsp_util = require "coq.producers.lsp.util"
local mpmc = require "coq.lib.channels.mpmc"
local util = require "coq.producers.util"

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

local kinds = vim.lsp.protocol.CompletionTriggerKind

---@class lsp.CompletionTracker
---@field trigger_kind integer
---@field parse_items fun(value: lsp.CompletionList|lsp.CompletionItem[]|nil): lsp.CompletionItem[]
---@field commit fun()

---@param client vim.lsp.Client
---@param buf integer
---@return lsp.CompletionTracker
local completion_tracker = function(client, buf)
  local incomplete_var = "__coq_lsp_incomplete_" .. client.id
  local incomplete = false

  ---@diagnostic disable-next-line: missing-fields
  local tracker = {} ---@type lsp.CompletionTracker

  tracker.trigger_kind = vim.b[buf][incomplete_var] and kinds.TriggerForIncompleteCompletions or kinds.Invoked

  tracker.parse_items = function(value)
    if type(value) ~= "table" then
      return {}
    end
    incomplete = incomplete or value.isIncomplete == true
    if value.items ~= nil then
      return value.items
    end
    return value
  end

  tracker.commit = function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.b[buf][incomplete_var] = incomplete or nil
    end
  end

  return tracker
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
    local tracker = completion_tracker(client, ctx.buf)
    defer(tracker.commit)
    local row, col = unpack(ctx.pos)

    local params = {
      position = { line = row - 1, character = encode_col(ctx.line, col, client.offset_encoding) },
      textDocument = td_params,
      context = { triggerKind = tracker.trigger_kind },
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
          chan.push(tracker.parse_items(args.data.params.value))
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
      coroutine.yield(tracker.parse_items(result))
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
