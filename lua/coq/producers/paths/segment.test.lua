local T = require "coq.lib.test"
local segment = require "coq.producers.paths.segment"

T.describe("paths.segment.p_lhs", function(test)
  test("returns '.' when lhs ends with curdir", function()
    T.eq(segment.p_lhs ".", ".")
    T.eq(segment.p_lhs "foo/.", ".")
  end)

  test("returns '..' when lhs ends with pardir (preferred over '.')", function()
    T.eq(segment.p_lhs "..", "..")
    T.eq(segment.p_lhs "foo/..", "..")
  end)

  test("returns '~' when lhs ends with tilde", function()
    T.eq(segment.p_lhs "~", "~")
    T.eq(segment.p_lhs "cd ~", "~")
  end)

  test("returns '' when lhs has no special prefix", function()
    T.eq(segment.p_lhs "", "")
    T.eq(segment.p_lhs "foo", "")
    T.eq(segment.p_lhs "/foo", "")
  end)

  test("captures $VAR when env is set", function()
    vim.env.COQ_TEST_PATHS = "/spot"
    T.eq(segment.p_lhs "$COQ_TEST_PATHS", "$COQ_TEST_PATHS")
    T.eq(segment.p_lhs "cd $COQ_TEST_PATHS", "$COQ_TEST_PATHS")
    vim.env.COQ_TEST_PATHS = nil
  end)

  test("ignores $VAR when env is unset", function()
    vim.env.COQ_TEST_UNSET = nil
    T.eq(segment.p_lhs "$COQ_TEST_UNSET", "")
  end)

  test("captures ${VAR}", function()
    T.eq(segment.p_lhs "${HOME}", "${HOME}")
    T.eq(segment.p_lhs "cd ${PATH}", "${PATH}")
  end)
end)

T.describe("paths.segment.split_keep", function(test)
  test("yields empty leading segment when text starts with sep", function()
    T.eq(segment.split_keep("/", "/foo"), { "", "/foo" })
  end)

  test("keeps sep at start of non-first segments", function()
    T.eq(segment.split_keep("/", "foo/bar"), { "foo", "/bar" })
    T.eq(segment.split_keep("/", "./foo/bar"), { ".", "/foo", "/bar" })
  end)

  test("text with no sep yields single segment", function()
    T.eq(segment.split_keep("/", "foo"), { "foo" })
  end)
end)

T.describe("paths.segment.iter_cuts", function(test)
  test("yields one cut per split boundary", function()
    local cuts = segment.iter_cuts({ ["/"] = true }, "foo/bar")
    T.eq(#cuts, 1)
    T.eq(cuts[1].segment, "foo")
    T.eq(cuts[1].s0, "/bar")
  end)

  test("applies p_lhs to the lhs to canonicalize the prefix", function()
    local cuts = segment.iter_cuts({ ["/"] = true }, "./foo/bar")
    T.eq(#cuts, 2)
    T.eq(cuts[1].segment, ".")
    T.eq(cuts[1].s0, "./foo/bar")
    T.eq(cuts[2].segment, "/foo")
    T.eq(cuts[2].s0, "/bar")
  end)

  test("preserves leading absolute paths via empty lhs", function()
    local cuts = segment.iter_cuts({ ["/"] = true }, "/etc/spot")
    T.eq(#cuts, 2)
    T.eq(cuts[1].segment, "")
    T.eq(cuts[1].s0, "/etc/spot")
  end)
end)

T.describe("paths.segment.p_sep", function(test)
  test("returns '/' on unix-like", function()
    if segment.is_windows then
      return
    end
    T.eq(segment.p_sep "foo/bar", "/")
    T.eq(segment.p_sep "foo\\bar", "/")
  end)
end)

T.describe("paths.segment.rpartition", function(test)
  test("splits at the last sep", function()
    local l, s, r = segment.rpartition("foo/bar/baz", "/")
    T.eq(l, "foo/bar")
    T.eq(s, "/")
    T.eq(r, "baz")
  end)

  test("returns ('', '', s) when no sep", function()
    local l, s, r = segment.rpartition("spot", "/")
    T.eq(l, "")
    T.eq(s, "")
    T.eq(r, "spot")
  end)
end)

T.describe("paths.segment.expanduser", function(test)
  test("expands leading ~/ to $HOME", function()
    local home = vim.uv.os_homedir()
    T.eq(segment.expanduser "~/spot", home .. "/spot")
    T.eq(segment.expanduser "~", home)
  end)

  test("leaves non-tilde paths untouched", function()
    T.eq(segment.expanduser "/etc", "/etc")
    T.eq(segment.expanduser "foo~bar", "foo~bar")
  end)
end)

T.describe("paths.segment.expandvars", function(test)
  test("expands $VAR and ${VAR} from env", function()
    vim.env.COQ_TEST_DOG = "fido"
    T.eq(segment.expandvars "/$COQ_TEST_DOG/spot", "/fido/spot")
    T.eq(segment.expandvars "${COQ_TEST_DOG}/spot", "fido/spot")
    vim.env.COQ_TEST_DOG = nil
  end)

  test("leaves unset vars literal", function()
    vim.env.COQ_TEST_GHOST = nil
    T.eq(segment.expandvars "$COQ_TEST_GHOST/spot", "$COQ_TEST_GHOST/spot")
  end)
end)
