local T = require "coq.lib.test"
local parse = require "coq.producers.paths.parse"
local path = require "coq.lib.path"
local tokens = require "coq.lib.index.tokens"

local i = parse

local ENV = { HOME = "/home/dogs", DOG_DIR = "/var/dogs", USERPROFILE = [[C:\Users\dogs]] }
local HOME = ENV.HOME
local UNIX, WIN = false, true
local SU, SW = path.seps(UNIX), path.seps(WIN)

-- vim default isfname, simplified to cover the chars we use in these tests.
-- @ = alpha, plus separators and the punctuation we exercise.
local UNIX_ISFNAME = tokens.parse_charset "@,48-57,/,.,-,_,+,~,$,@-@,{,}"
local WIN_ISFNAME = tokens.parse_charset "@,48-57,/,\\,.,-,_,+,~,$,@-@,{,},:,%,(,)"

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

  test("no head, returns token unchanged", function()
    T.eq(i._expand_head(UNIX, HOME, ENV, "kennel/spot", SU), "kennel/spot")
  end)

  test("on windows, ~\\... expands to HOME with backslash", function()
    T.eq(i._expand_head(WIN, [[C:\Users\dogs]], ENV, [[~\Documents]], SW), [[C:\Users\dogs\Documents]])
  end)
end)

T.describe("paths.parse.candidate", function(test)
  local unix_opts = { is_windows = UNIX, env = ENV, home = HOME, isfname = UNIX_ISFNAME }
  local win_opts = { is_windows = WIN, env = ENV, home = HOME, isfname = WIN_ISFNAME }

  test("no token returns nil", function()
    T.eq(parse.candidate("", unix_opts), nil)
  end)

  test("token with no separator returns nil", function()
    T.eq(parse.candidate("labrador", unix_opts), nil)
  end)

  test("~/Doc — start at 0, dir=HOME/, partial=Doc, absolute", function()
    local c = assert(parse.candidate("~/Doc", unix_opts))
    T.eq(c.start, 0)
    T.eq(c.resolved_directory, "/home/dogs/")
    T.eq(c.partial, "Doc")
    T.eq(c.absolute, true)
  end)

  test("$DOG_DIR/golden expands", function()
    local c = assert(parse.candidate("$DOG_DIR/golden", unix_opts))
    T.eq(c.start, 0)
    T.eq(c.resolved_directory, "/var/dogs/")
    T.eq(c.partial, "golden")
  end)

  test("cp /tmp/b — start after the space", function()
    local c = assert(parse.candidate("cp /tmp/b", unix_opts))
    T.eq(c.start, 3)
    T.eq(c.resolved_directory, "/tmp/")
    T.eq(c.partial, "b")
  end)

  test("/tmp/b — single candidate at line start", function()
    local c = assert(parse.candidate("/tmp/b", unix_opts))
    T.eq(c.start, 0)
    T.eq(c.resolved_directory, "/tmp/")
    T.eq(c.partial, "b")
  end)

  test("trailing slash — partial empty", function()
    local c = assert(parse.candidate("/var/dogs/", unix_opts))
    T.eq(c.resolved_directory, "/var/dogs/")
    T.eq(c.partial, "")
  end)

  test("on windows, backslash path resolves", function()
    local c = assert(parse.candidate([[C:\Dogs\lab]], win_opts))
    T.eq(c.resolved_directory, [[C:\Dogs\]])
    T.eq(c.partial, "lab")
    T.eq(c.absolute, true)
  end)
end)
