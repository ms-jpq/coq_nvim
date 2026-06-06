local T = require "coq.lib.test"
local path = require "coq.lib.path"

local UNIX, WIN = false, true
local SU, SW = path.seps(UNIX), path.seps(WIN)

T.describe({ "path.seps" }, function(test)
  test({ "unix default is just /" }, function()
    T.eq(path.seps(UNIX), { ["/"] = true })
  end)

  test({ "windows default is / and backslash" }, function()
    T.eq(path.seps(WIN), { ["/"] = true, ["\\"] = true })
  end)
end)

T.describe({ "path.is_absolute" }, function(test)
  test({ "/ is absolute" }, function()
    T.eq(path.is_absolute(UNIX, "/var/dogs"), true)
  end)

  test({ "relative is not" }, function()
    T.eq(path.is_absolute(UNIX, "dogs/spot"), false)
  end)

  test({ "empty is not" }, function()
    T.eq(path.is_absolute(UNIX, ""), false)
  end)

  test({ "on windows, backslash root is absolute" }, function()
    T.eq(path.is_absolute(WIN, [[\dogs]]), true)
  end)

  test({ "on windows, drive letter with backslash is absolute" }, function()
    T.eq(path.is_absolute(WIN, [[C:\dogs]]), true)
  end)

  test({ "on windows, drive letter with forward slash is absolute" }, function()
    T.eq(path.is_absolute(WIN, "C:/dogs"), true)
  end)

  test({ "on windows, drive-relative (no sep) is NOT absolute" }, function()
    T.eq(path.is_absolute(WIN, "C:dogs"), false)
  end)

  test({ "on unix, backslash root is not absolute" }, function()
    T.eq(path.is_absolute(UNIX, [[\dogs]]), false)
  end)
end)

T.describe({ "path.split_at_last_sep" }, function(test)
  test({ "splits at last /, dir keeps trailing sep" }, function()
    local dir, rhs = path.split_at_last_sep(SU, "/var/dogs/lab")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "lab")
  end)

  test({ "trailing / yields empty rhs" }, function()
    local dir, rhs = path.split_at_last_sep(SU, "/var/dogs/")
    T.eq(dir, "/var/dogs/")
    T.eq(rhs, "")
  end)

  test({ "no separator returns empty dir, whole input as rhs" }, function()
    local dir, rhs = path.split_at_last_sep(SU, "labrador")
    T.eq(dir, "")
    T.eq(rhs, "labrador")
  end)

  test({ "on windows, both / and \\ count as separators" }, function()
    local dir, rhs = path.split_at_last_sep(SW, [[C:\Dogs/lab]])
    T.eq(dir, [[C:\Dogs/]])
    T.eq(rhs, "lab")
  end)
end)

T.describe({ "path.stem" }, function(test)
  test({ "strips dir and extension" }, function()
    T.eq(path.stem "/home/user/spot.lua", "spot")
    T.eq(path.stem "lil.snip", "lil")
  end)
  test({ "no extension leaves the basename intact" }, function()
    T.eq(path.stem "/etc/Makefile", "Makefile")
  end)
  test({ "compound extensions strip only the last segment" }, function()
    T.eq(path.stem "/tmp/fido.tar.gz", "fido.tar")
  end)
  test({ "dotfile basename is treated as the name, not an extension" }, function()
    T.eq(path.stem ".bashrc", ".bashrc")
    T.eq(path.stem "/home/user/.hidden", ".hidden")
    T.eq(path.stem ".foo.txt", ".foo")
  end)
end)

T.describe({ "path.join" }, function(test)
  test({ "absolute p ignores base" }, function()
    T.eq(path.join("/home/dogs", "/etc/spot"), "/etc/spot")
  end)

  test({ "relative p joins under base" }, function()
    T.eq(path.join("/home/dogs", "spot.txt"), "/home/dogs/spot.txt")
  end)

  test({ "empty base returns p as-is" }, function()
    T.eq(path.join("", "spot.txt"), "spot.txt")
  end)
end)
