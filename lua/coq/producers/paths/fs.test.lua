local T = require "coq.lib.test"
local fs = require "coq.producers.paths.fs"

local i = fs._internal

local ENV = { HOME = "/home/dogs", DOG_DIR = "/var/dogs", USERPROFILE = [[C:\Users\dogs]] }
local HOME = ENV.HOME
local UNIX, WIN = false, true

T.describe("paths.fs.is_path_shape", function(test)
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

T.describe("paths.fs.expand_head", function(test)
  test("~/ expands to HOME", function()
    T.eq(i.expand_head(UNIX, "~/Documents", ENV, HOME), "/home/dogs/Documents")
  end)

  test("bare ~ expands to HOME", function()
    T.eq(i.expand_head(UNIX, "~", ENV, HOME), "/home/dogs")
  end)

  test("~user does not expand (no per-user resolution)", function()
    T.eq(i.expand_head(UNIX, "~labrador/Documents", ENV, HOME), "~labrador/Documents")
  end)

  test("$VAR expands when defined", function()
    T.eq(i.expand_head(UNIX, "$DOG_DIR/golden", ENV, HOME), "/var/dogs/golden")
  end)

  test("$VAR leaves token unchanged when undefined", function()
    T.eq(i.expand_head(UNIX, "$UNKNOWN/foo", ENV, HOME), "$UNKNOWN/foo")
  end)

  test("${VAR} expands when defined", function()
    T.eq(i.expand_head(UNIX, "${DOG_DIR}/labrador", ENV, HOME), "/var/dogs/labrador")
  end)

  test("no head, returns token unchanged", function()
    T.eq(i.expand_head(UNIX, "kennel/spot", ENV, HOME), "kennel/spot")
  end)

  test("on windows, ~\\... expands to HOME with backslash", function()
    T.eq(i.expand_head(WIN, [[~\Documents]], ENV, [[C:\Users\dogs]]), [[C:\Users\dogs\Documents]])
  end)

  test("on windows, %VAR% expands", function()
    T.eq(i.expand_head(WIN, "%USERPROFILE%/Dogs", ENV, HOME), [[C:\Users\dogs/Dogs]])
  end)

  test("on unix, %VAR% does not expand", function()
    T.eq(i.expand_head(UNIX, "%USERPROFILE%/Dogs", ENV, HOME), "%USERPROFILE%/Dogs")
  end)
end)

T.describe("paths.fs.is_absolute", function(test)
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

  test("on windows, drive letter is absolute", function()
    T.eq(i.is_absolute(WIN, [[C:\dogs]]), true)
  end)

  test("on unix, backslash root is not absolute", function()
    T.eq(i.is_absolute(UNIX, [[\dogs]]), false)
  end)
end)

T.describe("paths.fs.split_at_last_sep", function(test)
  local seps = { ["/"] = true }

  test("splits at last /, dir keeps trailing sep", function()
    local dir, rhs = i.split_at_last_sep("/var/dogs/lab", seps)
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "lab")
  end)

  test("trailing / yields empty rhs", function()
    local dir, rhs = i.split_at_last_sep("/var/dogs/", seps)
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "")
  end)

  test("no separator yields empty dir, whole path as rhs", function()
    local dir, rhs = i.split_at_last_sep("labrador", seps)
    T.eq(dir, "")
    T.eq(rhs, "labrador")
  end)

  test("respects windows seps when both / and \\ are recognized", function()
    local both = { ["/"] = true, ["\\"] = true }
    local dir, rhs = i.split_at_last_sep([[C:\Dogs/lab]], both)
    T.eq(dir, [[C:\Dogs/]])
    T.eq(rhs, "lab")
  end)
end)

T.describe("paths.fs.parse", function(test)
  local opts = { is_windows = UNIX, env = ENV, home = HOME }

  test("nil when no path shape", function()
    T.eq(fs.parse("labrador", opts), nil)
  end)

  test("bare ~ expands and splits at HOME's parent", function()
    -- ~ → /home/dogs; split → dir=/home/, rhs=dogs. Treating bare ~ as ~/ is a
    -- UX call for the matcher (would require is_dir check); fs.parse stays pure.
    local p = assert(fs.parse("~", opts))
    T.eq(p.dir_resolved, "/home/")
    T.eq(p.rhs, "dogs")
    T.eq(p.is_absolute, true)
  end)

  test("absolute path with rhs", function()
    local p = assert(fs.parse("/var/dogs/lab", opts))
    T.eq(p.dir_resolved, "/var/dogs/")
    T.eq(p.rhs, "lab")
    T.eq(p.is_absolute, true)
    T.eq(p.segment_start, 0)
  end)

  test("~/path expands and splits", function()
    local p = assert(fs.parse("~/Dogs/lab", opts))
    T.eq(p.dir_resolved, "/home/dogs/Dogs/")
    T.eq(p.rhs, "lab")
    T.eq(p.is_absolute, true)
  end)

  test("$VAR/path expands and splits", function()
    local p = assert(fs.parse("$DOG_DIR/golden", opts))
    T.eq(p.dir_resolved, "/var/dogs/")
    T.eq(p.rhs, "golden")
    T.eq(p.is_absolute, true)
  end)

  test("${VAR}/path expands and splits", function()
    local p = assert(fs.parse("${DOG_DIR}/", opts))
    T.eq(p.dir_resolved, "/var/dogs/")
    T.eq(p.rhs, "")
    T.eq(p.is_absolute, true)
  end)

  test("relative dir/rhs", function()
    local p = assert(fs.parse("kennel/spot", opts))
    T.eq(p.dir_resolved, "kennel/")
    T.eq(p.rhs, "spot")
    T.eq(p.is_absolute, false)
  end)

  test("./relative", function()
    local p = assert(fs.parse("./kennel/", opts))
    T.eq(p.dir_resolved, "./kennel/")
    T.eq(p.rhs, "")
    T.eq(p.is_absolute, false)
  end)

  test("trailing sep ⇒ enumerate everything inside dir", function()
    local p = assert(fs.parse("/var/dogs/", opts))
    T.eq(p.dir_resolved, "/var/dogs/")
    T.eq(p.rhs, "")
  end)

  test("windows: C:\\Dogs\\lab splits with backslash", function()
    local p = assert(fs.parse([[C:\Dogs\lab]], { is_windows = WIN, env = ENV, home = ENV.USERPROFILE }))
    T.eq(p.dir_resolved, [[C:\Dogs\]])
    T.eq(p.rhs, "lab")
    T.eq(p.is_absolute, true)
  end)

  test("windows: %USERPROFILE%\\Dogs expands and splits", function()
    local p = assert(fs.parse([[%USERPROFILE%\Dogs]], { is_windows = WIN, env = ENV, home = ENV.USERPROFILE }))
    T.eq(p.dir_resolved, [[C:\Users\dogs\]])
    T.eq(p.rhs, "Dogs")
    T.eq(p.is_absolute, true)
  end)
end)
