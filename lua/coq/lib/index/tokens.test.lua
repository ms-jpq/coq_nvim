local T = require "coq.lib.test"
local atools = require "coq.lib.atools"
local tokens = require "coq.lib.index.tokens"

local CORPUS = {
  -- prose
  "the quick brown fox jumps over the lazy dog",
  "she sells seashells by the seashore",
  "",
  "   leading and trailing whitespace   ",
  "\t\ttabs\tand\tspaces  mixed\t",

  -- identifiers
  "foo_bar = baz123 + qux42",
  "camelCase PascalCase snake_case SCREAMING_SNAKE",
  "kebab-case dash-separated multi-word-name",
  "_private __dunder __init__",
  "x1 x2 x_10 x_y_z foo2bar3baz",
  "a b c d e f g h i j k l m n o p q r s t u v w x y z",
  "A1B2C3 0xDEADBEEF 0b1010 1_000_000 3.14e-10",

  -- punctuation and operators
  "obj.field->ptr::method(arg).chain()",
  "tag1 #anchor @mention $var %record &ref *deref",
  "let x = 42; const NAME = 'literal'",
  "// comment with [brackets] {braces} (parens) <angles>",
  "1 + 2 == 3, a*b/c, x|y&z, p^q~r",
  "-- lua-style; vim:set noexpandtab number",
  "a-b c-d-e --flag --no-flag",
  "x?y:z ??coalesce !!truthy ===strict",
  "<<<heredoc >>output |>pipe <|reverse",

  -- code shapes
  "def fetch(url, *, timeout=30, retries=3): pass",
  "function* gen(): AsyncIterator<string> { yield 'a' }",
  "fn add<T: Add>(a: T, b: T) -> T { a + b }",
  "type User = { id: number; name: string; tags: string[] }",
  "trait Shape where Self: Sized + Send + 'static {}",
  "(defun fact (n) (if (<= n 1) 1 (* n (fact (- n 1)))))",
  "SELECT * FROM users WHERE id = 42 AND active = true;",
  "git@github.com:user/repo.git refs/heads/main^{tree}",

  -- paths & urls
  "/usr/local/bin/zsh ./relative/path file.tar.gz",
  "https://example.com:8080/path?q=1&r=2#frag",
  "C:\\Users\\foo\\AppData ~/.config/nvim/init.lua",

  -- edge cases
  "...",
  "------",
  "______",
  "12345",
  "a",
  "!",
  "@@@",
  "key=value;other=thing,nested[0].field",
  "line one\nstill line one for our purposes",

  -- common english with contractions and punctuation tails
  "it's John's dog -- isn't it?",
  "don't can't won't shouldn't",
  "Mr. Dr. Sr. Jr. e.g. i.e. etc.",
  "2026-05-30T12:34:56Z +0000",
  "v1.2.3-beta+build.42",
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

T.test("tokens.parity across all filetypes", function()
  local failures = {}

  for _, ft in pairs(enumerate_filetypes()) do
    atools.scheduled()
    local iskeyword, expected = probe(ft)
    local kw = tokens.parse_iskeyword(iskeyword)
    local actual = vim.iter(tokens.words(kw, vim.iter(CORPUS) --[[@as fun(): string?]])):totable()
    if not vim.deep_equal(actual, expected) then
      table.insert(failures, { ft = ft, iskeyword = iskeyword, expected = expected, actual = actual })
    end
  end

  T.eq(failures, {})
end)

T.describe("tokens.trailing_keyword_before", function(test)
  local kw = tokens.parse_iskeyword "@,48-57,_"

  test("empty line returns empty", function()
    T.eq(tokens.trailing_keyword_before(kw, ""), "")
  end)

  test("returns the trailing keyword substring", function()
    T.eq(tokens.trailing_keyword_before(kw, "hello"), "hello")
    T.eq(tokens.trailing_keyword_before(kw, "foo bar"), "bar")
    T.eq(tokens.trailing_keyword_before(kw, "obj.method"), "method")
  end)

  test("non-keyword tail returns empty", function()
    T.eq(tokens.trailing_keyword_before(kw, "hello "), "")
    T.eq(tokens.trailing_keyword_before(kw, "foo."), "")
  end)

  test("respects iskeyword: hyphen excluded by default", function()
    T.eq(tokens.trailing_keyword_before(kw, "kebab-case"), "case")
  end)

  test("respects iskeyword: hyphen included when configured", function()
    local with_dash = tokens.parse_iskeyword "@,48-57,_,-"
    T.eq(tokens.trailing_keyword_before(with_dash, "kebab-case"), "kebab-case")
  end)
end)
