local T = require "coq.lib.test"
local parse = require "coq.producers.paths.parse"
local path = require "coq.lib.path"

local i = parse

local ENV = { HOME = "/home/dogs", DOG_DIR = "/var/dogs", USERPROFILE = [[C:\Users\dogs]] }
local HOME = ENV.HOME
local UNIX, WIN = false, true
local SU, SW = path.seps(UNIX), path.seps(WIN)

T.describe({ "paths.parse.expand_env" }, function(test)
  test({ "$VAR expands when defined" }, function()
    T.eq(i._expand_env(UNIX, ENV, "$DOG_DIR/golden"), "/var/dogs/golden")
  end)

  test({ "$VAR unchanged when undefined" }, function()
    T.eq(i._expand_env(UNIX, ENV, "$UNKNOWN/foo"), "$UNKNOWN/foo")
  end)

  test({ "${VAR} expands when defined" }, function()
    T.eq(i._expand_env(UNIX, ENV, "${DOG_DIR}/labrador"), "/var/dogs/labrador")
  end)

  test({ "no head, returns token unchanged" }, function()
    T.eq(i._expand_env(UNIX, ENV, "kennel/spot"), "kennel/spot")
  end)

  test({ "on windows, %VAR% expands" }, function()
    T.eq(i._expand_env(WIN, ENV, "%USERPROFILE%/Dogs"), [[C:\Users\dogs/Dogs]])
  end)

  test({ "on unix, %VAR% does not expand" }, function()
    T.eq(i._expand_env(UNIX, ENV, "%USERPROFILE%/Dogs"), "%USERPROFILE%/Dogs")
  end)

  test({ "does NOT touch ~ (that's expand_head's job)" }, function()
    T.eq(i._expand_env(UNIX, ENV, "~/Dogs"), "~/Dogs")
  end)
end)

T.describe({ "paths.parse.expand_head" }, function(test)
  test({ "~/ expands to HOME" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~/Documents", SU), "/home/dogs/Documents")
  end)

  test({ "bare ~ expands to HOME" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~", SU), "/home/dogs")
  end)

  test({ "~user does not expand (no per-user resolution)" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "~labrador/Documents", SU), "~labrador/Documents")
  end)

  test({ "$VAR expands when defined" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "$DOG_DIR/golden", SU), "/var/dogs/golden")
  end)

  test({ "${VAR} expands when defined" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "${DOG_DIR}/labrador", SU), "/var/dogs/labrador")
  end)

  test({ "no head, returns token unchanged" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "kennel/spot", SU), "kennel/spot")
  end)

  test({ "on windows, ~\\... expands to HOME with backslash" }, function()
    T.eq(i._expand_head(WIN, [[C:\Users\dogs]], ENV, [[~\Documents]], SW), [[C:\Users\dogs\Documents]])
  end)

  test({ "@<path> strips the @ — cwd anchoring happens at cand_dirs" }, function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "@lua/coq", SU), "lua/coq")
  end)
end)

T.describe({ "paths.parse.patterns" }, function(test)
  test({ "unix list does not include backslash- or windows-only shapes" }, function()
    for p in i._patterns(UNIX, SU) do
      assert(not string.find(p, "\\", 1, true), "pattern should not include backslash: " .. p)
      assert(not string.find(p, "%%", 1, true), "pattern should not include literal %%: " .. p)
      assert(not string.find(p, "%a:", 1, true), "pattern should not include drive letter: " .. p)
    end
  end)

  test({ "windows yields head patterns for every separator" }, function()
    local by_sep = { ["/"] = 0, ["\\"] = 0 }
    for p in i._patterns(WIN, SW) do
      local tail = string.sub(p, -1)
      if by_sep[tail] ~= nil then
        by_sep[tail] = by_sep[tail] + 1
      end
    end
    T.eq(by_sep["/"], by_sep["\\"])
    assert(by_sep["/"] > 0, "expected patterns ending in /")
    assert(by_sep["\\"] > 0, "expected patterns ending in backslash")
  end)
end)

T.describe({ "paths.parse.find_starts" }, function(test)
  ---@return table[]
  local collect = function(is_win, line)
    local out = {}
    for pos, token in i._find_starts(is_win, path.seps(is_win), line) do
      table.insert(out, { pos, token })
    end
    return out
  end

  test({ "empty when nothing path-shaped in line" }, function()
    T.eq(collect(UNIX, "labrador"), {})
    T.eq(collect(UNIX, "cp foo bar"), {})
  end)

  test({ "~/Dogs — ~ head at 1, empty-head + / at 2" }, function()
    T.eq(collect(UNIX, "~/Dogs"), {
      { 1, "~/Dogs" },
      { 2, "/Dogs" },
    })
  end)

  test({ "/tmp/lab — empty-head + / at every slash" }, function()
    T.eq(collect(UNIX, "/tmp/lab"), {
      { 1, "/tmp/lab" },
      { 5, "/lab" },
    })
  end)

  test({ "./Dogs — . head at 1, / at 2" }, function()
    T.eq(collect(UNIX, "./Dogs"), {
      { 1, "./Dogs" },
      { 2, "/Dogs" },
    })
  end)

  test({ "$DOG_DIR/golden — $VAR head at 1, / at 9" }, function()
    T.eq(collect(UNIX, "$DOG_DIR/golden"), {
      { 1, "$DOG_DIR/golden" },
      { 9, "/golden" },
    })
  end)

  test({ "${DOG_DIR}/golden — ${VAR} head at 1, / at 11" }, function()
    T.eq(collect(UNIX, "${DOG_DIR}/golden"), {
      { 1, "${DOG_DIR}/golden" },
      { 11, "/golden" },
    })
  end)

  test({ "on unix, backslash-separated input yields no starts" }, function()
    T.eq(collect(UNIX, [[Documents\spot]]), {})
  end)
end)

T.describe({ "paths.parse.candidates" }, function(test)
  local opts = { is_windows = UNIX, env = ENV, home = HOME }

  ---@param iter lib.Iterator<paths.parse.Candidate>
  ---@return table[]
  local strip = function(iter)
    local out = {}
    for c in iter do
      table.insert(out, {
        start = c.start,
        dir = c.resolved_directory,
        partial = c.partial,
        anchor = c.anchor,
      })
    end
    return out
  end

  test({ "empty when no head pattern matches" }, function()
    T.eq(strip(parse.candidates("labrador", opts)), {})
  end)

  test({ "empty when token has no sep and no head" }, function()
    T.eq(strip(parse.candidates("cp foo bar", opts)), {})
  end)

  test({ "~/Doc — single candidate at line start" }, function()
    local cs = strip(parse.candidates("~/Doc", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/home/dogs/")
    T.eq(cs[1].partial, "Doc")
    T.eq(cs[1].anchor, parse.ANCHOR.abs)
  end)

  test({ "$VAR/golden expands" }, function()
    local cs = strip(parse.candidates("$DOG_DIR/golden", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/var/dogs/")
    T.eq(cs[1].partial, "golden")
  end)

  test({ "${VAR}/golden expands" }, function()
    local cs = strip(parse.candidates("${DOG_DIR}/golden", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "/var/dogs/")
    T.eq(cs[1].partial, "golden")
  end)

  test({ "cp /tmp/b — candidate at /tmp/ with partial=b" }, function()
    local cs = strip(parse.candidates("cp /tmp/b", opts))
    local hit = false
    for _, c in pairs(cs) do
      if c.dir == "/tmp/" and c.partial == "b" then
        hit = true
        break
      end
    end
    assert(hit, "expected a candidate with dir=/tmp/ and partial=b")
  end)

  test({ "/tmp/b yields one candidate per slash" }, function()
    local cs = strip(parse.candidates("/tmp/b", opts))
    local starts = {}
    for _, c in pairs(cs) do
      table.insert(starts, c.start)
    end
    table.sort(starts)
    T.eq(starts, { 0, 4 })
  end)

  test({ "leftmost-first ordering" }, function()
    local cs = strip(parse.candidates("/tmp/b", opts))
    for k = 2, #cs do
      assert(cs[k - 1].start <= cs[k].start, "candidates must be leftmost-first")
    end
  end)

  test({ "@<path>/ — cwd-anchored, literal keeps the @" }, function()
    local cs = strip(parse.candidates("@lua/", opts))
    T.eq(cs[1].start, 0)
    T.eq(cs[1].dir, "lua/")
    T.eq(cs[1].partial, "")
    T.eq(cs[1].anchor, parse.ANCHOR.cwd)
  end)

  test({ "@lua/coq/in — literal_directory keeps the @" }, function()
    local cand = nil
    for c in parse.candidates("@lua/coq/in", opts) do
      cand = c
      break
    end
    assert(cand, "expected a candidate")
    T.eq(cand.literal_directory, "@lua/coq/")
    T.eq(cand.partial, "in")
    T.eq(cand.anchor, parse.ANCHOR.cwd)
  end)

  test({ "on windows, backslash path yields a candidate" }, function()
    local win_opts = { is_windows = WIN, env = ENV, home = HOME }
    local cs = strip(parse.candidates([[C:\Dogs\lab]], win_opts))
    local hit = false
    for _, c in pairs(cs) do
      if c.dir == [[C:\Dogs\]] and c.partial == "lab" then
        hit = true
        break
      end
    end
    assert(hit, [[expected a candidate with dir=C:\Dogs\ and partial=lab]])
  end)
end)
