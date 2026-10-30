local T = require "coq.lib.test"
local async = require "coq.lib.async"

local acceptance = [[
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.completeopt = "menuone,noselect,noinsert"
vim.o.showmode = false
vim.opt.shortmess:append "c"
local async = require "coq.lib.async"
local settings = require("coq.config").merged()
local applied = 0
local check = function(fn)
  return function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      io.stderr:write(tostring(err))
      os.exit(1)
    end
  end
end
local additional = {
  { newText = "import", range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } } },
}
local item = {
  word = "fido", abbr = case.bullet and (string.char(226, 128, 162) .. " fido") or "fido", kind = "",
  meta = { uid = "test", source = "LSP", filter = "fi", fuzzy = 0 },
}
if not case.plain then
  item.meta.lsp = {
    position_encoding = "utf-8",
    item = {
      label = "fido",
      insertTextFormat = case.snippet and 2 or 1,
      textEdit = {
        newText = case.snippet or "fido",
        range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 2 } },
      },
      additionalTextEdits = case.known and additional or nil,
    },
  }
end

vim.api.nvim_buf_set_lines(0, 0, -1, true, { "", "fi" })
vim.api.nvim_win_set_cursor(0, { 2, 1 })
vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true })
async.entry(function()
  local n = require("coq.lib.async._nursery").new()
  require("coq.completions.events").new()
  require("coq.completions.insertion").bind(n, settings, {
    resolve = function()
      if case.resolved then
        async.sleep(20)
        return { item = { additionalTextEdits = additional } }
      end
    end,
  }, { inserted = function() applied = applied + 1 end })
end)()

vim.api.nvim_create_autocmd("InsertEnter", {
  once = true,
  callback = function()
    vim.schedule(check(function()
      vim.fn.complete(1, { require("coq.completions.item").to_nvim(settings.display.icons, item) })
      vim.api.nvim_input("<C-n>" .. case.keys)
      vim.defer_fn(check(function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
        assert(vim.deep_equal(lines, case.expected), vim.inspect({ actual = lines, expected = case.expected }))
        assert(applied == (case.cancel and 0 or 1), "unexpected completion application count")
        vim.cmd "qa!"
      end), 150)
    end))
  end,
})
vim.api.nvim_input "A"
]]

T.describe({ "completion acceptance" }, function(test)
  for _, case in ipairs {
    { name = "plain word followed by punctuation", plain = true, keys = ":", expected = { "", "fido:" } },
    { name = "LSP edit followed by punctuation", keys = ":", expected = { "", "fido:" } },
    { name = "LSP edit followed by multiple characters", keys = ".name", expected = { "", "fido.name" } },
    { name = "LSP edit followed by UTF-8 input", keys = "\195\169", expected = { "", "fido\195\169" } },
    { name = "explicit accept followed by typing", keys = "<C-y>:", expected = { "", "fido:" } },
    { name = "Enter accept followed by typing", keys = "<CR>:", expected = { "", "fido:" } },
    { name = "snippet followed by typing", snippet = "fido$0", keys = ":", expected = { "", "fido:" } },
    {
      name = "bullet snippet followed by typing",
      snippet = "fido$0",
      bullet = true,
      keys = ":",
      expected = { "", "fido:" },
    },
    {
      name = "typing into a snippet placeholder",
      snippet = "fido(${1})$0",
      keys = ":",
      expected = { "", "fido(:)" },
    },
    { name = "known additional edit with typing", known = true, keys = ":", expected = { "import", "fido:" } },
    {
      name = "resolved additional edit without typing",
      resolved = true,
      keys = "<C-y>",
      expected = { "import", "fido" },
    },
    { name = "stale resolved edit is skipped", resolved = true, keys = ":", expected = { "", "fido:" } },
    {
      name = "known additional edit is not applied twice",
      known = true,
      resolved = true,
      keys = "<C-y>",
      expected = { "import", "fido" },
    },
    { name = "cancel does not apply edits", known = true, keys = "<C-e>", cancel = true, expected = { "", "fi" } },
  } do
    test({ case.name, timeout = 5000 * T.SLOW }, function()
      local code = "local case = vim.json.decode(" .. string.format("%q", vim.json.encode(case)) .. ")\n" .. acceptance
      local result = async.awaitify(vim.system)({
        vim.v.progpath,
        "--headless",
        "-n",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "-c",
        "lua " .. code,
      }, { timeout = 3000 * T.SLOW })
      T.eq(result, { code = 0, signal = 0, stdout = "", stderr = "" })
    end)
  end
end)
