local T = require "coq.lib.test"
local tokens = require "coq.lib.index.tokens"

local CORPUS = {
  "the quick brown fox",
  "foo_bar = baz123 + qux42",
  "kebab-case and snake_case mixed",
  "obj.field->ptr::method(arg)",
  "tag1 #anchor @mention $var %rec",
  "let x = 42; const NAME = 'literal'",
  "// comment with [brackets] {braces} (parens)",
  "1 + 2 == 3, a*b/c, x|y&z",
  "-- lua-style; vim:set noexpandtab",
  "a-b c-d-e --flag --no-flag",
  "",
  "   leading and trailing   ",
}

---@return string[]
local enumerate_filetypes = function()
  local seen = {}
  for _, ext in pairs { "vim", "lua" } do
    for _, path in pairs(vim.api.nvim_get_runtime_file("ftplugin/*." .. ext, true)) do
      local name = vim.fs.basename(path)
      local ft = string.gsub(name, "%." .. ext .. "$", "")
      seen[ft] = true
    end
  end
  return vim
    .iter(seen)
    :map(function(k)
      return k
    end)
    :totable()
end

---@param ft string
---@return string iskeyword
---@return string[] expected
local probe = function(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = ft
  local iskeyword = vim.bo[buf].iskeyword
  local expected = vim.api.nvim_buf_call(buf, function()
    return vim
      .iter(vim.fn.matchstrlist(CORPUS, [[\k\+]]))
      :map(function(m)
        return m.text
      end)
      :totable()
  end)
  vim.api.nvim_buf_delete(buf, { force = true })
  return iskeyword, expected
end

T.describe("tokens.parity", function(test)
  for _, ft in pairs(enumerate_filetypes()) do
    test(ft, function()
      local iskeyword, expected = probe(ft)
      local kw = tokens.parse_iskeyword(iskeyword)
      local actual = vim.iter(tokens.words(kw, vim.iter(CORPUS) --[[@as fun(): string?]])):totable()
      T.eq(actual, expected)
    end)
  end
end)
