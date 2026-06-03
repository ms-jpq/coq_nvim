local T = require "coq.lib.test"
local parse = require "coq.producers.paths.parse"

local i = parse

local ENV = { HOME = "/home/dogs", DOG_DIR = "/var/dogs", USERPROFILE = [[C:\Users\dogs]] }
local HOME = ENV.HOME
local UNIX, WIN = false, true
local SU, SW = i._seps(UNIX, {}), i._seps(WIN, {})

T.describe("paths.parse.seps", function(test)
  test("unix default is just /", function()
    T.eq(i._seps(UNIX, {}), { ["/"] = true })
  end)

  test("windows default is / and backslash", function()
    T.eq(i._seps(WIN, {}), { ["/"] = true, ["\\"] = true })
  end)

  test("whitelist keeps only listed OS seps", function()
    T.eq(i._seps(WIN, { "/" }), { ["/"] = true })
  end)

  test("empty whitelist falls back to all OS seps", function()
    T.eq(i._seps(WIN, {}), { ["/"] = true, ["\\"] = true })
  end)

  test("no overlap falls back to all OS seps", function()
    -- backslash is not a unix sep, so the filter is empty -> fall back to /
    T.eq(i._seps(UNIX, { "\\" }), { ["/"] = true })
  end)

  test("non-sep characters are ignored, not added", function()
    T.eq(i._seps(UNIX, { ":", "|" }), { ["/"] = true })
  end)
end)

T.describe("paths.parse.expand_env", function(test)
  test("$VAR expands when defined", function()
    T.eq(i._expand_env(UNIX, ENV, "$DOG_DIR/golden"), "/var/dogs/golden")
  end)

  test("$VAR unchanged when undefined", function()
    T.eq(i._expand_env(UNIX, ENV, "$UNKNOWN/foo"), "$UNKNOWN/foo")
  end)

  test("${VAR} expands when defined", function()
    T.eq(i._expand_env(UNIX, ENV, "${DOG_DIR}/labrador"), "/var/dogs/labrador")
  end)

  test("no head, returns token unchanged", function()
    T.eq(i._expand_env(UNIX, ENV, "kennel/spot"), "kennel/spot")
  end)

  test("on windows, %VAR% expands", function()
    T.eq(i._expand_env(WIN, ENV, "%USERPROFILE%/Dogs"), [[C:\Users\dogs/Dogs]])
  end)

  test("on unix, %VAR% does not expand", function()
    T.eq(i._expand_env(UNIX, ENV, "%USERPROFILE%/Dogs"), "%USERPROFILE%/Dogs")
  end)

  test("does NOT touch ~ (that's expand_head's job)", function()
    T.eq(i._expand_env(UNIX, ENV, "~/Dogs"), "~/Dogs")
  end)
end)

T.describe("paths.parse.expand_head", function(test)
  test("~/ expands to HOME", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~/Documents", SU), "/home/dogs/Documents")
  end)

  test("bare ~ expands to HOME", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~", SU), "/home/dogs")
  end)

  test("~user does not expand (no per-user resolution)", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~labrador/Documents", SU), "~labrador/Documents")
  end)

  test("$VAR expands when defined", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "$DOG_DIR/golden", SU), "/var/dogs/golden")
  end)

  test("$VAR leaves token unchanged when undefined", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "$UNKNOWN/foo", SU), "$UNKNOWN/foo")
  end)

  test("${VAR} expands when defined", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "${DOG_DIR}/labrador", SU), "/var/dogs/labrador")
  end)

  test("no head, returns token unchanged", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "kennel/spot", SU), "kennel/spot")
  end)

  test("on windows, ~\\... expands to HOME with backslash", function()
    T.eq(i._expand_head(WIN, [[C:\Users\dogs]], ENV, [[~\Documents]], SW), [[C:\Users\dogs\Documents]])
  end)

  test("on windows, %VAR% expands", function()
    T.eq(i._expand_head(WIN, HOME, ENV, "%USERPROFILE%/Dogs", SW), [[C:\Users\dogs/Dogs]])
  end)

  test("on unix, %VAR% does not expand", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "%USERPROFILE%/Dogs", SU), "%USERPROFILE%/Dogs")
  end)
end)

T.describe("paths.parse.is_absolute", function(test)
  test("/ is absolute", function()
    T.eq(i._is_absolute(UNIX, SU, "/var/dogs"), true)
  end)

  test("relative is not", function()
    T.eq(i._is_absolute(UNIX, SU, "dogs/spot"), false)
  end)

  test("empty is not", function()
    T.eq(i._is_absolute(UNIX, SU, ""), false)
  end)

  test("on windows, backslash root is absolute", function()
    T.eq(i._is_absolute(WIN, SW, [[\dogs]]), true)
  end)

  test("on windows, drive letter with backslash is absolute", function()
    T.eq(i._is_absolute(WIN, SW, [[C:\dogs]]), true)
  end)

  test("on windows, drive letter with forward slash is absolute", function()
    T.eq(i._is_absolute(WIN, SW, "C:/dogs"), true)
  end)

  test("on windows, drive-relative (no sep) is NOT absolute", function()
    T.eq(i._is_absolute(WIN, SW, "C:dogs"), false)
  end)

  test("on windows, bare drive letter is NOT absolute", function()
    T.eq(i._is_absolute(WIN, SW, "C:"), false)
  end)

  test("on windows, url-like scheme is NOT absolute", function()
    T.eq(i._is_absolute(WIN, SW, "https://dogs.example"), false)
  end)

  test("on unix, backslash root is not absolute", function()
    T.eq(i._is_absolute(UNIX, SU, [[\dogs]]), false)
  end)
end)

T.describe("paths.parse.split_at_last_sep", function(test)
  test("splits at last /, dir keeps trailing sep", function()
    local dir, rhs = i._split_at_last_sep(SU, "/var/dogs/lab")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "lab")
  end)

  test("trailing / yields empty rhs", function()
    local dir, rhs = i._split_at_last_sep(SU, "/var/dogs/")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "")
  end)

  test("no separator returns nil dir", function()
    local dir = i._split_at_last_sep(SU, "labrador")
    T.eq(dir, nil)
  end)

  test("on windows, both / and \\ count as separators", function()
    local dir, rhs = i._split_at_last_sep(SW, [[C:\Dogs/lab]])
    T.eq(dir, [[C:\Dogs/]])
    T.eq(rhs, "lab")
  end)

  test("on unix, backslash is not a separator (stays in dir)", function()
    local dir, rhs = i._split_at_last_sep(SU, [[/some\path/file]])
    T.eq(dir, [[/some\path/]])
    T.eq(rhs, "file")
  end)
end)

T.describe("paths.parse.patterns", function(test)
  test("unix list does not include backslash- or windows-only shapes", function()
    for p in i._patterns(UNIX, SU) do
      assert(not string.find(p, "\\", 1, true), "pattern should not include backslash: " .. p)
      assert(not string.find(p, "%%", 1, true), "pattern should not include literal %%: " .. p)
      assert(not string.find(p, "%a:", 1, true), "pattern should not include drive letter: " .. p)
    end
  end)

  test("windows yields head patterns for every separator (no exhausted iterator)", function()
    local by_sep = { ["/"] = 0, ["\\"] = 0 }
    for p in i._patterns(WIN, SW) do
      local tail = string.sub(p, -1)
      if by_sep[tail] ~= nil then
        by_sep[tail] = by_sep[tail] + 1
      end
    end
    -- both seps must get the full head set; the old single-use `pats` drained
    -- after the first sep, leaving the second with zero patterns.
    T.eq(by_sep["/"], by_sep["\\"])
    assert(by_sep["/"] > 0, "expected patterns ending in /")
    assert(by_sep["\\"] > 0, "expected patterns ending in backslash")
  end)
end)

T.describe("paths.parse.find_starts", function(test)
  ---@return table[]
  local collect = function(is_win, line)
    local out = {}
    for pos, token in i._find_starts(is_win, i._seps(is_win, {}), line) do
      table.insert(out, { pos, token })
    end
    return out
  end

  test("empty when nothing path-shaped in line", function()
    T.eq(collect(UNIX, "labrador"), {})
    T.eq(collect(UNIX, "cp foo bar"), {})
  end)

  test("~/Dogs — ~ head at 1, empty-head + / at 2", function()
    T.eq(collect(UNIX, "~/Dogs"), {
      { 1, "~/Dogs" },
      { 2, "/Dogs" },
    })
  end)

  test("/tmp/lab — empty-head + / at every slash", function()
    T.eq(collect(UNIX, "/tmp/lab"), {
      { 1, "/tmp/lab" },
      { 5, "/lab" },
    })
  end)

  test("~/Dogs/lab — sorted, dedup-by-position", function()
    T.eq(collect(UNIX, "~/Dogs/lab"), {
      { 1, "~/Dogs/lab" },
      { 2, "/Dogs/lab" },
      { 7, "/lab" },
    })
  end)

  test("./Dogs — . head at 1, / at 2", function()
    T.eq(collect(UNIX, "./Dogs"), {
      { 1, "./Dogs" },
      { 2, "/Dogs" },
    })
  end)

  test("$DOG_DIR/golden — $VAR head at 1, / at 9", function()
    T.eq(collect(UNIX, "$DOG_DIR/golden"), {
      { 1, "$DOG_DIR/golden" },
      { 9, "/golden" },
    })
  end)

  test("on unix, backslash-separated input yields no starts", function()
    T.eq(collect(UNIX, [[Documents\spot]]), {})
  end)
end)

T.describe("paths.parse.candidates", function(test)
  local opts = { is_windows = UNIX, env = ENV, home = HOME, path_seps = {} }

  ---@param iter lib.Iterator<paths.parse.Candidate>
  ---@return table[]  -- pruned shape for easier assertion
  local strip = function(iter)
    local out = {}
    for c in iter do
      table.insert(out, { start = c.start, dir = c.resolved_directory, partial = c.partial, abs = c.absolute })
    end
    return out
  end

  test("empty when no head pattern matches", function()
    T.eq(strip(parse.candidates("labrador", opts)), {})
  end)

  test("empty when token has no sep and no head", function()
    T.eq(strip(parse.candidates("cp foo bar", opts)), {})
  end)

  test("~/Doc — single candidate at line start", function()
    local cs = strip(parse.candidates("~/Doc", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/home/dogs/")
    T.eq(cs[1].partial, "Doc")
    T.eq(cs[1].abs, true)
  end)

  test("$VAR/golden expands", function()
    local cs = strip(parse.candidates("$DOG_DIR/golden", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/var/dogs/")
    T.eq(cs[1].partial, "golden")
  end)

  test("`cp /tmp/b` yields a candidate at /tmp/ with partial=b", function()
    -- head patterns don't span spaces (no pattern has space + sep), so the
    -- candidates that exist naturally start at/after the space.
    local cs = strip(parse.candidates("cp /tmp/b", opts))
    local hit = false
    for _, c in ipairs(cs) do
      if c.dir == "/tmp/" and c.partial == "b" then
        hit = true
        break
      end
    end
    assert(hit, "expected a candidate with dir=/tmp/ and partial=b")
  end)

  test("/tmp/b yields one candidate per slash", function()
    -- empty-head + `/` matches at positions 1 and 5 → segment_starts 0 and 4
    local cs = strip(parse.candidates("/tmp/b", opts))
    local starts = {}
    for _, c in ipairs(cs) do
      table.insert(starts, c.start)
    end
    table.sort(starts)
    T.eq(starts, { 0, 4 })
  end)

  test("leftmost-first ordering", function()
    local cs = strip(parse.candidates("/tmp/b", opts))
    -- prior cases just sorted; this checks the function actually returns sorted
    for k = 2, #cs do
      assert(cs[k - 1].start <= cs[k].start, "candidates must be leftmost-first")
    end
  end)

  test("on windows, backslash path yields a candidate (both seps active)", function()
    local win_opts = { is_windows = WIN, env = ENV, home = HOME, path_seps = {} }
    local cs = strip(parse.candidates([[C:\Dogs\lab]], win_opts))
    local hit = false
    for _, c in ipairs(cs) do
      if c.dir == [[C:\Dogs\]] and c.partial == "lab" then
        hit = true
        break
      end
    end
    assert(hit, [[expected a candidate with dir=C:\Dogs\ and partial=lab]])
  end)

  test("path_seps whitelist drops backslash on windows", function()
    -- C:/Dogs\lab : with both seps the last sep is `\` (dir=C:/Dogs\, partial=lab);
    -- honoring only `/` makes `\` ordinary, so the split is at `/` (dir=C:/,
    -- partial=Dogs\lab).
    local default_opts = { is_windows = WIN, env = ENV, home = HOME, path_seps = {} }
    local default_cs = strip(parse.candidates([[C:/Dogs\lab]], default_opts))
    local default_hit = false
    for _, c in ipairs(default_cs) do
      if c.dir == [[C:/Dogs\]] and c.partial == "lab" then
        default_hit = true
      end
    end
    assert(default_hit, [[default: expected dir=C:/Dogs\ partial=lab]])

    local slash_only = { is_windows = WIN, env = ENV, home = HOME, path_seps = { "/" } }
    local cs = strip(parse.candidates([[C:/Dogs\lab]], slash_only))
    local hit = false
    for _, c in ipairs(cs) do
      if c.dir == "C:/" and c.partial == [[Dogs\lab]] then
        hit = true
      end
    end
    assert(hit, [[whitelist {/}: expected dir=C:/ partial=Dogs\lab (backslash not a sep)]])
  end)
end)
