local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local cancel = nil

local str_utfindex = vim.str_utfindex

local function make_position_param(row, col)
  row = row - 1
  local line = api.nvim_buf_get_lines(0, row, row+1, true)[1]
  col = str_utfindex(line, col)
  return { line = row; character = col; }
end


local list_comp_candidates = function (request_id, row, col)
  if cancel then
    cancel()
    cancel = nil
  end

  if #lsp.buf_get_clients() == 0 then
    fn._FCnotify("lsp", request_id, nil)
  else
    local position = make_position_param(row, col)
    local text_doc = lsp.util.make_text_document_params()
    local params = {position = position, textDocument=text_doc}

    _, cancel = lsp.buf_request(0, "textDocument/completion", params, function (err, _, ans)
      assert(not err and ans, err)
      fn._FCnotify("lsp", request_id, ans)
    end)
  end
end


return {
  list_comp_candidates = list_comp_candidates
}
