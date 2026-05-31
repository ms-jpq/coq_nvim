local T = require "coq.lib.test"
local async = require "coq.lib.async"
local config = require "coq.config"
local paths = require "coq.producers.paths"

local touch = function(path)
  local f = assert(io.open(path, "w"))
  f:close()
end

---@return string
local tmpdir = function()
  local p = vim.fn.tempname()
  vim.fn.mkdir(p)
  return p
end

---@param overrides? table
---@return config.Settings
local settings_with = function(overrides)
  return config.merged(overrides)
end

---@param ctx_overrides table
---@return ctx.full
local ctx_of = function(ctx_overrides)
  local base = {
    win = 0,
    buf = 0,
    pos = { 1, 0 },
    changedtick = 0,
    cwd = "/",
    filetype = "",
    filename = "",
    cword = "",
    cexpr = "",
    tabstop = 2,
    expandtab = true,
    iskeyword = "@,48-57,_,192-255",
    kw = {},
    linesep = "\n",
    comment = { "", "" },
    line_count = 1,
    line = "",
    line_before = "",
    line_after = "",
    keyword_before = "",
    utf16_col = 0,
    utf32_col = 0,
  }
  return vim.tbl_deep_extend("force", base, ctx_overrides) --[[@as ctx.full]]
end

---@param settings config.Settings
---@param ctx ctx.full
---@return any[]
local run_matcher = function(settings, ctx)
  local items = {}
  async.scope(function()
    for item in
      async.wrap(function()
        paths.matcher(settings, ctx)
      end)
    do
      table.insert(items, item)
    end
  end)
  return items
end

---@param items table[]
---@return string[]
local words_of = function(items)
  local out = {}
  for _, it in ipairs(items) do
    table.insert(out, it.word)
  end
  table.sort(out)
  return out
end

T.describe("paths.matcher", function(test)
  test("./ lists the cwd as files and folders", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    vim.fn.mkdir(dir .. "/fido")
    vim.fn.mkdir(dir .. "/rex")

    local settings = settings_with()
    local ctx = ctx_of { cwd = dir, line_before = "./", line = "./" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "fido/", "rex/", "spot.txt" })
  end)

  test("kind is Folder for dirs, File for files", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    vim.fn.mkdir(dir .. "/fido")

    local settings = settings_with()
    local ctx = ctx_of { cwd = dir, line_before = "./", line = "./" }

    local items = run_matcher(settings, ctx)
    local kinds = {}
    for _, it in ipairs(items) do
      kinds[it.word] = it.kind
    end
    T.eq(kinds["spot.txt"], "File")
    T.eq(kinds["fido/"], "Folder")
  end)

  test("prefix-filters entries within a directory", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    touch(dir .. "/scout.txt")
    touch(dir .. "/fido.txt")

    local settings = settings_with()
    local ctx = ctx_of { cwd = dir, line_before = "./sp", line = "./sp" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "spot.txt" })
  end)

  test("prefix match is case-insensitive", function()
    local dir = tmpdir()
    touch(dir .. "/Spot.txt")
    touch(dir .. "/Fido.txt")

    local settings = settings_with()
    local ctx = ctx_of { cwd = dir, line_before = "./sp", line = "./sp" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "Spot.txt" })
  end)

  test("absolute path lists from /", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")

    local settings = settings_with()
    local ctx = ctx_of { cwd = "/nowhere", line_before = dir .. "/", line = dir .. "/" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "spot.txt" })
  end)

  test("~ expands to home", function()
    local home = assert(vim.uv.os_homedir())
    local settings = settings_with()
    local ctx = ctx_of { cwd = "/", line_before = "~/", line = "~/" }

    local items = run_matcher(settings, ctx)
    local home_listing = {}
    for name in vim.fs.dir(home) do
      home_listing[name] = true
    end

    for _, it in ipairs(items) do
      local bare = string.gsub(it.word, "/$", "")
      T.eq(home_listing[bare] or false, true)
    end
  end)

  test("$VAR expands when set", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    vim.uv.os_setenv("COQ_TEST_PATHS_DIR", dir)

    local settings = settings_with()
    local ctx = ctx_of { cwd = "/", line_before = "$COQ_TEST_PATHS_DIR/", line = "$COQ_TEST_PATHS_DIR/" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "spot.txt" })

    vim.uv.os_unsetenv "COQ_TEST_PATHS_DIR"
  end)

  test("returns nothing when no resolution base is available", function()
    local settings = settings_with { clients = { paths = { resolution = {} } } }
    local ctx = ctx_of { cwd = "/", line_before = "./", line = "./" }

    local items = run_matcher(settings, ctx)
    T.eq(items, {})
  end)

  test("file-base resolves to the directory of the current file", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")
    touch(dir .. "/fido.txt")
    local fake_file = dir .. "/current.lua"
    touch(fake_file)

    local settings = settings_with { clients = { paths = { resolution = { "file" } } } }
    local ctx = ctx_of { cwd = "/nowhere", filename = fake_file, line_before = "./sp", line = "./sp" }

    local items = run_matcher(settings, ctx)
    T.eq(words_of(items), { "spot.txt" })
  end)

  test("emits lsp textEdit spanning the segment, not just the keyword", function()
    local dir = tmpdir()
    touch(dir .. "/spot.txt")

    local settings = settings_with()
    local ctx = ctx_of {
      cwd = dir,
      pos = { 1, 4 },
      line_before = "./sp",
      line = "./sp",
      utf16_col = 4,
    }

    local items = run_matcher(settings, ctx)
    T.eq(#items, 1)

    local lsp = items[1].meta.lsp
    T.eq(lsp.position_encoding, "utf-8")
    local edit = lsp.item.textEdit
    T.eq(edit.range.start.line, 0)
    T.eq(edit.range.start.character, 0)
    T.eq(edit.range["end"].character, 4)
    T.eq(edit.newText, "./spot.txt")
  end)
end)
