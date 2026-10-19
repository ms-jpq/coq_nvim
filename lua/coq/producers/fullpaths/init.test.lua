local T = require "coq.lib.test"
local TH = require "coq.lib.test_helpers"
local async = require "coq.lib.async"
local config = require "coq.config"
local fullpaths = require "coq.producers.fullpaths"
local inserted = require "coq.completions.inserted"
local lib = require "coq.lib"
local parse = require "coq.producers.fullpaths.parse"

T.describe({ "fullpaths.partial" }, function(test)
  ---@type [string, integer?, string?][]
  local cases = {
    { "@", 0, "" },
    { "@kennel/lil", 0, "kennel/lil" },
    { "see @lil", 4, "lil" },
    { '"@lil', 1, "lil" },
    { "(@lil", 1, "lil" },
    { "dogs@example.com", 4, "example.com" },
    { "/dogs/@lil", 6, "lil" },
    { '@lil"', 0, 'lil"' },
    { "@lil<>|", 0, "lil<>|" },
    { "@lil@wang", 4, "wang" },
    { "@lil @", 5, "" },
    { "@lil next", 0, "lil next" },
    { "dogs" },
  }
  for _, case in pairs(cases) do
    local line, start, partial = unpack(case)
    ---@cast line string
    test({ line }, function()
      local cand = parse.candidate(line, { symbol = "@", is_windows = false })
      T.eq(cand and { cand.start, cand.partial } or {}, { start, partial })
    end)
  end
end)

T.describe({ "fullpaths.partial custom symbol" }, function(test)
  for _, symbol in pairs { "%", "[", "$", "::", "🐶" } do
    test({ symbol }, function()
      local opts = { symbol = symbol, is_windows = false }
      local cand = assert(parse.candidate("see " .. symbol .. "kennel/lil", opts))
      T.eq({ cand.start, cand.partial }, { 4, "kennel/lil" })
      T.eq(parse.candidate("@lil", opts), nil)
      local embedded = assert(parse.candidate("dogs" .. symbol .. "lil", opts))
      T.eq({ embedded.start, embedded.partial }, { 4, "lil" })
    end)
  end

  test({ "empty symbol does not trigger" }, function()
    T.eq(parse.candidate("kennel/lil", { symbol = "", is_windows = false }), nil)
  end)
end)

T.describe({ "fullpaths.matcher" }, function(test)
  test({ "searches full relative paths and applies an @ replacement" }, function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/kennel", "p")
    vim.fn.mkdir(root .. "/.git", "p")
    for _, name in pairs { "kennel/lil.txt", "kennel/wang.txt", "ignored.txt", ".hidden", ".git/private" } do
      vim.fn.writefile({}, root .. "/" .. name)
    end
    vim.fn.writefile({ "ignored.txt" }, root .. "/.ignore")
    local settings = config.merged()
    local collect = function(line, filename)
      local ctx = TH.ctx_of {
        cwd = root,
        filename = filename or "",
        line = line,
        line_before = line,
        keyword_before = line:match "[%w_]+$" or "",
        pos = { 1, #line, #line, #line },
        wildignore = "*wang*,.ignore",
      }
      local items = {}
      local pull = async.wrap(function()
        fullpaths.matcher(settings, ctx)
      end)
      for batch in pull do
        vim.list_extend(items, batch)
      end
      return items, ctx
    end

    local items, ctx = collect "see @kll"
    T.eq(#items, 1)
    local item = items[1]
    T.eq(item.word, "@kennel/lil.txt")
    T.eq(item.meta.path, root .. "/kennel/lil.txt")
    T.eq(item.meta.always_on_top, true)
    T.eq(item.meta.lsp.item.textEdit.range.start.character, 4)

    lib.scope(function(defer)
      local producer = fullpaths.new()
      defer(producer.close)
      local close, iter = producer.search(settings, ctx)
      defer(close)
      local threaded = {}
      for batch in iter do
        vim.list_extend(threaded, batch)
      end
      T.eq(#threaded, 1)
      T.eq(threaded[1].word, item.word)
    end)

    local buf = TH.scratch_buf { "see @" .. item.word }
    ctx.buf = buf
    ctx.pos = { 1, #("see @" .. item.word) }
    inserted._apply_edits(ctx, item, item.meta.lsp.item.textEdit, {})
    T.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { "see @kennel/lil.txt" })
    vim.api.nvim_buf_delete(buf, { force = true })

    local words = vim.tbl_map(function(i)
      return i.word
    end, collect "@")
    table.sort(words)
    T.eq(words, { "@.git/private", "@.hidden", "@ignored.txt", "@kennel/lil.txt" })
    T.eq(collect "dogs@example.com", {})
    settings.clients.fullpaths.resolution = { "file" }
    T.eq(collect "@lil", {})
    local from_file = collect("@lil", root .. "/kennel/current.lua")
    T.eq(#from_file, 1)
    T.eq(from_file[1].word, "@lil.txt")
    T.eq(from_file[1].meta.path, root .. "/kennel/lil.txt")

    settings.clients.fullpaths.resolution = { "cwd", "file" }
    local both = collect("@lil", root .. "/kennel/current.lua")
    T.eq(#both, 2)
    local same_base = collect("@lil", root .. "/current.lua")
    T.eq(#same_base, 1)

    settings.clients.fullpaths.resolution = {}
    T.eq(collect("@lil", root .. "/kennel/current.lua"), {})
    settings.clients.fullpaths.resolution = { "cwd" }
    settings.clients.fullpaths.symbol = "%"
    local custom, custom_ctx = collect "see %kll"
    T.eq(#custom, 1)
    T.eq(custom[1].word, "%kennel/lil.txt")
    local custom_buf = TH.scratch_buf { "see %" .. custom[1].word }
    custom_ctx.buf = custom_buf
    custom_ctx.pos = { 1, #("see %" .. custom[1].word) }
    inserted._apply_edits(custom_ctx, custom[1], custom[1].meta.lsp.item.textEdit, {})
    T.eq(vim.api.nvim_buf_get_lines(custom_buf, 0, -1, true), { "see %kennel/lil.txt" })
    vim.api.nvim_buf_delete(custom_buf, { force = true })
    T.eq(collect "@kll", {})
    vim.fn.delete(root, "rf")
  end)
end)
