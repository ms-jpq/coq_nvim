local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local cancel = function () end

return function (chan_id, request_id, row, col)
  if cancel then
    cancel()
  end
  cancel = nil

  local position = {line = row, character = col}
  local text_doc = lsp.util.make_text_document_params()
  local params = {position = position, textDocument=text_doc}

  _, cancel = lsp.buf_request(0, "textDocument/completion", params, function (_, _, ret)
    vim.notify(chan_id, "", request_id, ret)
  end)
end

