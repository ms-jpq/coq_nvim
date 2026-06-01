local async = require "coq.lib.async"
local atools = require "coq.lib.atools"
local runtime = require "coq.lib.async.runtime"

---@class lsp.RequestItem
---@field client_id integer
---@field client_name string
---@field offset_encoding string
---@field kind string
---@field item lsp.CompletionItem

local M = {}

-- Runs on the main thread; called via `worker.main_stream`.
-- Fires `textDocument/completion` per attached LSP client and yields each
-- returned CompletionItem with its provenance.
---@param buf integer
---@param row integer 0-indexed
---@param col integer byte column
M.query = function(buf, row, col)
  local h = runtime.current()

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  local clients = vim.lsp.get_clients { bufnr = buf, method = "textDocument/completion" }
  if #clients == 0 then
    return
  end

  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1] or ""
  local td_params = vim.lsp.util.make_text_document_params(buf)
  local kinds = vim.lsp.protocol.CompletionItemKind

  for i, client in ipairs(clients) do
    if i > 1 then
      atools.scheduled()
    end
    if h.cancelled then
      return
    end

    local encoded_col = col
    if client.offset_encoding == "utf-16" then
      encoded_col = vim.str_utfindex(line, "utf-16", col, true)
    elseif client.offset_encoding == "utf-32" then
      encoded_col = vim.str_utfindex(line, "utf-32", col, true)
    end

    local params = {
      position = { line = row, character = encoded_col },
      textDocument = td_params,
      context = { triggerKind = 1 },
    }

    local f = async.future()
    local ok, req_id = client:request("textDocument/completion", params, function(err, result)
      f.resolve(err, result)
    end, buf)

    if ok and req_id then
      local unwatch = h.on_cancel(function()
        client:cancel_request(req_id)
      end)

      local err, result = f.await(h)
      unwatch()

      if not err and result and not h.cancelled then
        local items = type(result) == "table" and (result.items or result) or {}
        local client_id = client.id
        local client_name = client.name
        local enc = client.offset_encoding
        for _, item in ipairs(items) do
          if h.cancelled then
            return
          end
          coroutine.yield {
            client_id = client_id,
            client_name = client_name,
            offset_encoding = enc,
            kind = kinds[item.kind or 0] or "",
            item = item,
          }
        end
      end
    end
  end
end

return M
