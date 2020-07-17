local lsp = vim.lsp


local list_comp_candidates = function ()
  local pos = lsp.util.make_position_params()

  local clients, cancel = unpack(lsp.buf_request(0, "textDocument/completion", pos, function (err, _, results)
    assert(not err, err)

    print(vim.inspect(results))

  end))
end


return {
  list_comp_candidates = list_comp_candidates
}
