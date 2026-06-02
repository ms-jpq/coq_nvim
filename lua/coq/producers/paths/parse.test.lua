local T = require "coq.lib.test"
local parse = require "coq.producers.paths.parse"

local i = parse._internal

local ENV = { HOME = "/home/dogs", DOG_DIR = "/var/dogs", USERPROFILE = [[C:\Users\dogs]] }
local HOME = ENV.HOME
local UNIX, WIN = false, true

T.describe("paths.parse.is_path_shape", function(test)
  test("rejects bare identifier", function()
    T.eq(i.is_path_shape(UNIX, "labrador"), false)
  end)

  test("rejects empty", function()
    T.eq(i.is_path_shape(UNIX, ""), false)
  end)

  test("accepts anything containing a forward slash", function()
    T.eq(i.is_path_shape(UNIX, "kennel/spot"), true)
  end)

  test("accepts leading ~", function()
    T.eq(i.is_path_shape(UNIX, "~dogs"), true)
  end)

  test("accepts leading $ for $VAR", function()
    T.eq(i.is_path_shape(UNIX, "$DOG_DIR"), true)
  end)

  test("accepts bare . and ..", function()
    T.eq(i.is_path_shape(UNIX, "."), true)
    T.eq(i.is_path_shape(UNIX, ".."), true)
  end)

  test("rejects .gitignore (dot-prefixed file, no sep)", function()
    T.eq(i.is_path_shape(UNIX, ".gitignore"), false)
  end)

  test("on unix, backslash is not a path char", function()
    T.eq(i.is_path_shape(UNIX, [[Documents\spot]]), false)
  end)

  test("on windows, backslash counts", function()
    T.eq(i.is_path_shape(WIN, [[Documents\spot]]), true)
  end)

  test("on windows, drive letter counts", function()
    T.eq(i.is_path_shape(WIN, [[C:\Dogs]]), true)
  end)

  test("on windows, %VAR% counts", function()
    T.eq(i.is_path_shape(WIN, "%USERPROFILE%"), true)
  end)

  test("on unix, drive-letter pattern does not", function()
    T.eq(i.is_path_shape(UNIX, "C:foo"), false)
  end)
end)

T.describe("paths.parse.expand_env", function(test)
  test("$VAR expands when defined", function()
    T.eq(i.expand_env(UNIX, ENV, "$DOG_DIR/golden"), "/var/dogs/golden")
  end)

  test("$VAR unchanged when undefined", function()
    T.eq(i.expand_env(UNIX, ENV, "$UNKNOWN/foo"), "$UNKNOWN/foo")
  end)

  test("${VAR} expands when defined", function()
    T.eq(i.expand_env(UNIX, ENV, "${DOG_DIR}/labrador"), "/var/dogs/labrador")
  end)

  test("no head, returns token unchanged", function()
    T.eq(i.expand_env(UNIX, ENV, "kennel/spot"), "kennel/spot")
  end)

  test("on windows, %VAR% expands", function()
    T.eq(i.expand_env(WIN, ENV, "%USERPROFILE%/Dogs"), [[C:\Users\dogs/Dogs]])
  end)

  test("on unix, %VAR% does not expand", function()
    T.eq(i.expand_env(UNIX, ENV, "%USERPROFILE%/Dogs"), "%USERPROFILE%/Dogs")
  end)

  test("does NOT touch ~ (that's expand_head's job)", function()
    T.eq(i.expand_env(UNIX, ENV, "~/Dogs"), "~/Dogs")
  end)
end)

T.describe("paths.parse.expand_head", function(test)
  test("~/ expands to HOME", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "~/Documents"), "/home/dogs/Documents")
  end)

  test("bare ~ expands to HOME", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "~"), "/home/dogs")
  end)

  test("~user does not expand (no per-user resolution)", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "~labrador/Documents"), "~labrador/Documents")
  end)

  test("$VAR expands when defined", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "$DOG_DIR/golden"), "/var/dogs/golden")
  end)

  test("$VAR leaves token unchanged when undefined", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "$UNKNOWN/foo"), "$UNKNOWN/foo")
  end)

  test("${VAR} expands when defined", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "${DOG_DIR}/labrador"), "/var/dogs/labrador")
  end)

  test("no head, returns token unchanged", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "kennel/spot"), "kennel/spot")
  end)

  test("on windows, ~\\... expands to HOME with backslash", function()
    T.eq(i.expand_head(WIN, [[C:\Users\dogs]], ENV, [[~\Documents]]), [[C:\Users\dogs\Documents]])
  end)

  test("on windows, %VAR% expands", function()
    T.eq(i.expand_head(WIN, HOME, ENV, "%USERPROFILE%/Dogs"), [[C:\Users\dogs/Dogs]])
  end)

  test("on unix, %VAR% does not expand", function()
    T.eq(i.expand_head(UNIX, HOME, ENV, "%USERPROFILE%/Dogs"), "%USERPROFILE%/Dogs")
  end)
end)

T.describe("paths.parse.is_absolute", function(test)
  test("/ is absolute", function()
    T.eq(i.is_absolute(UNIX, "/var/dogs"), true)
  end)

  test("relative is not", function()
    T.eq(i.is_absolute(UNIX, "dogs/spot"), false)
  end)

  test("empty is not", function()
    T.eq(i.is_absolute(UNIX, ""), false)
  end)

  test("on windows, backslash root is absolute", function()
    T.eq(i.is_absolute(WIN, [[\dogs]]), true)
  end)

  test("on windows, drive letter with backslash is absolute", function()
    T.eq(i.is_absolute(WIN, [[C:\dogs]]), true)
  end)

  test("on windows, drive letter with forward slash is absolute", function()
    T.eq(i.is_absolute(WIN, "C:/dogs"), true)
  end)

  test("on windows, drive-relative (no sep) is NOT absolute", function()
    T.eq(i.is_absolute(WIN, "C:dogs"), false)
  end)

  test("on windows, bare drive letter is NOT absolute", function()
    T.eq(i.is_absolute(WIN, "C:"), false)
  end)

  test("on windows, url-like scheme is NOT absolute", function()
    T.eq(i.is_absolute(WIN, "https://dogs.example"), false)
  end)

  test("on unix, backslash root is not absolute", function()
    T.eq(i.is_absolute(UNIX, [[\dogs]]), false)
  end)
end)

T.describe("paths.parse.split_at_last_sep", function(test)
  test("splits at last /, dir keeps trailing sep", function()
    local dir, rhs = i.split_at_last_sep(UNIX, "/var/dogs/lab")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "lab")
  end)

  test("trailing / yields empty rhs", function()
    local dir, rhs = i.split_at_last_sep(UNIX, "/var/dogs/")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "")
  end)

  test("no separator returns nil dir", function()
    local dir = i.split_at_last_sep(UNIX, "labrador")
    T.eq(dir, nil)
  end)

  test("on windows, both / and \\ count as separators", function()
    local dir, rhs = i.split_at_last_sep(WIN, [[C:\Dogs/lab]])
    T.eq(dir, [[C:\Dogs/]])
    T.eq(rhs, "lab")
  end)

  test("on unix, backslash is not a separator (stays in dir)", function()
    local dir, rhs = i.split_at_last_sep(UNIX, [[/some\path/file]])
    T.eq(dir, [[/some\path/]])
    T.eq(rhs, "file")
  end)
end)

T.describe("paths.parse.default_patterns", function(test)
  test("unix list does not include backslash- or windows-only shapes", function()
    local pats = i.patterns(UNIX)
    for _, p in ipairs(pats) do
      assert(not string.find(p, "\\", 1, true), "pattern should not include backslash: " .. p)
      assert(not string.find(p, "%%", 1, true), "pattern should not include literal %%: " .. p)
      assert(not string.find(p, "%a:", 1, true), "pattern should not include drive letter: " .. p)
    end
  end)

  test("windows list adds %VAR%, drive, and backslash variants", function()
    local pats = i.patterns(WIN)
    local has = function(needle)
      for _, p in ipairs(pats) do
        if string.find(p, needle, 1, true) then
          return true
        end
      end
      return false
    end
    assert(has [[%%[%w_]+%%]], "windows patterns should include %VAR%")
    assert(has "%a:", "windows patterns should include drive letter")
    assert(has "\\", "windows patterns should include backslash sep")
  end)
end)

T.describe("paths.parse.candidates", function(test)
  local opts = { is_windows = UNIX, env = ENV, home = HOME }

  ---@param cs paths.parse.Candidate[]
  ---@return table[]  -- pruned shape for easier assertion
  local strip = function(cs)
    local out = {}
    for _, c in ipairs(cs) do
      table.insert(out, { start = c.segment_start, dir = c.dir_resolved, rhs = c.rhs, abs = c.is_absolute })
    end
    return out
  end

  test("empty when no head pattern matches", function()
    T.eq(parse.candidates("labrador", opts), {})
  end)

  test("empty when token has no sep and no head", function()
    T.eq(parse.candidates("cp foo bar", opts), {})
  end)

  test("~/Doc — single candidate at line start", function()
    local cs = strip(parse.candidates("~/Doc", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/home/dogs/")
    T.eq(cs[1].rhs, "Doc")
    T.eq(cs[1].abs, true)
  end)

  test("$VAR/golden expands", function()
    local cs = strip(parse.candidates("$DOG_DIR/golden", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/var/dogs/")
    T.eq(cs[1].rhs, "golden")
  end)

  test("ignores text past a non-path-interior char", function()
    -- the space between `cp` and `/tmp/b` blocks any candidate starting at or before the space
    local cs = strip(parse.candidates("cp /tmp/b", opts))
    for _, c in ipairs(cs) do
      assert(c.start >= 3, "candidate must start at or after the space: got " .. c.start)
    end
    -- one of the candidates resolves to dir=/tmp/, rhs=b
    local hit = false
    for _, c in ipairs(cs) do
      if c.dir == "/tmp/" and c.rhs == "b" then
        hit = true
        break
      end
    end
    assert(hit, "expected a candidate with dir=/tmp/ and rhs=b")
  end)

  test("absolute and relative candidates coexist", function()
    -- /tmp/b matches both `/` (start=0) and bare alnum `tmp/` (start=1)
    local cs = strip(parse.candidates("/tmp/b", opts))
    local starts = {}
    for _, c in ipairs(cs) do
      table.insert(starts, c.start)
    end
    table.sort(starts)
    T.eq(starts[1], 0)
    T.eq(starts[2], 1)
  end)

  test("leftmost-first ordering", function()
    local cs = strip(parse.candidates("/tmp/b", opts))
    -- prior cases just sorted; this checks the function actually returns sorted
    for k = 2, #cs do
      assert(cs[k - 1].start <= cs[k].start, "candidates must be leftmost-first")
    end
  end)

  test("windows: %USERPROFILE%\\Dogs", function()
    local cs = strip(parse.candidates([[%USERPROFILE%\Dogs]], { is_windows = WIN, env = ENV, home = ENV.USERPROFILE }))
    -- the first candidate (leftmost) is the %VAR% match
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, [[C:\Users\dogs\]])
    T.eq(cs[1].rhs, "Dogs")
    T.eq(cs[1].abs, true)
  end)

  test("windows: drive letter is captured leftmost", function()
    local cs = strip(parse.candidates([[C:\Dogs\lab]], { is_windows = WIN, env = ENV, home = ENV.USERPROFILE }))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, [[C:\Dogs\]])
    T.eq(cs[1].rhs, "lab")
  end)
end)
