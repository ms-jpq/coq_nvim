local T = require "coq.lib.test"
local parse = require "coq.producers.tags.parse"

T.describe("tags.parse", function(test)
  test("yields a single tag from one json line", function()
    local raw = vim.json.encode {
      _type = "tag",
      name = "lil",
      path = "/dogs/lil.py",
      line = 10,
      kind = "function",
      language = "Python",
      pattern = [[/^def lil():$/]],
    }
    local tags = vim.iter(parse.parse(raw)):totable()

    T.eq(#tags, 1)
    T.eq(tags[1].word, "lil")
    T.eq(tags[1].filename, "/dogs/lil.py")
    T.eq(tags[1].line, 10)
    T.eq(tags[1].kind, "function")
    T.eq(tags[1].filetype, "python")
    T.eq(tags[1].pattern, "def lil():")
  end)

  test("ignores non-tag entries and blank lines", function()
    local raw = table.concat({
      vim.json.encode { _type = "ptag", name = "TAG_FILE_SORTED" },
      "",
      vim.json.encode { _type = "tag", name = "spot", path = "/dogs/spot.py", line = 1 },
    }, "\n")
    local tags = vim.iter(parse.parse(raw)):totable()

    T.eq(#tags, 1)
    T.eq(tags[1].word, "spot")
  end)

  test("drops tag entries missing required name or path", function()
    local raw = table.concat({
      vim.json.encode { _type = "tag", path = "/dogs/no-name.py", line = 1 },
      vim.json.encode { _type = "tag", name = "no-path", line = 1 },
      vim.json.encode { _type = "tag", name = "fido", path = "/dogs/fido.py", line = 5 },
    }, "\n")
    local tags = vim.iter(parse.parse(raw)):totable()

    T.eq(#tags, 1)
    T.eq(tags[1].word, "fido")
  end)

  test("survives a malformed json line", function()
    local raw = table.concat({
      "{not json}",
      vim.json.encode { _type = "tag", name = "fido", path = "/dogs/fido.py", line = 5 },
    }, "\n")
    local tags = vim.iter(parse.parse(raw)):totable()

    T.eq(#tags, 1)
    T.eq(tags[1].word, "fido")
  end)

  test("forwards optional scope and signature fields", function()
    local raw = vim.json.encode {
      _type = "tag",
      name = "bark",
      path = "/dogs/lil.py",
      line = 2,
      kind = "method",
      language = "python",
      scope = "Lil",
      scopeKind = "class",
      access = "public",
      signature = "(self)",
      typeref = "typename:str",
    }
    local tag = vim.iter(parse.parse(raw)):totable()[1]

    T.eq(tag.scope, "Lil")
    T.eq(tag.scopeKind, "class")
    T.eq(tag.access, "public")
    T.eq(tag.signature, "(self)")
    T.eq(tag.typeref, "typename:str")
  end)
end)
