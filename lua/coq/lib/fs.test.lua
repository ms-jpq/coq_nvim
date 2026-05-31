local T = require "coq.lib.test"
local fs = require "coq.lib.fs"

T.describe("fs.fmt_path", function(test)
  test("returns '.' when path equals current", function()
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work/spot.txt", "/home/lil/work/spot.txt"), ".")
  end)

  test("returns ./rel when path is under cwd", function()
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work/spot.txt"), "./spot.txt")
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work/sub/fido.lua"), "./sub/fido.lua")
  end)

  test("returns . when path equals cwd", function()
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work"), ".")
  end)

  test("returns absolute when path is outside cwd and HOME", function()
    T.eq(fs.fmt_path("/home/lil/work", "/etc/passwd"), "/etc/passwd")
  end)

  test("treats current as winning over cwd-rel", function()
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work/spot.txt", "/home/lil/work/spot.txt"), ".")
    T.eq(fs.fmt_path("/home/lil/work", "/home/lil/work/fido.txt", "/home/lil/work/spot.txt"), "./fido.txt")
  end)

  test("does not expand $HOME / env in inputs", function()
    -- $HOME should be left literal; without expansion it can't match HOME-prefix.
    T.eq(fs.fmt_path("/home/lil/work", "$HOME/spot.txt"), "$HOME/spot.txt")
  end)
end)
