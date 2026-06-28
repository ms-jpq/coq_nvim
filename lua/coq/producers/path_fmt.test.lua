local T = require "coq.lib.test"
local path_fmt = require "coq.producers.path_fmt"

T.describe({ "path_fmt.fmt" }, function(test)
  test({ "returns '.' when path equals current" }, function()
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work/spot.txt", "/home/lil/work/spot.txt"), ".")
  end)

  test({ "returns ./rel when path is under cwd" }, function()
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work/spot.txt"), "./spot.txt")
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work/sub/fido.lua"), "./sub/fido.lua")
  end)

  test({ "returns . when path equals cwd" }, function()
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work"), ".")
  end)

  test({ "returns absolute when path is outside cwd and HOME" }, function()
    T.eq(path_fmt.fmt("/home/lil/work", "/etc/passwd"), "/etc/passwd")
  end)

  test({ "treats current as winning over cwd-rel" }, function()
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work/spot.txt", "/home/lil/work/spot.txt"), ".")
    T.eq(path_fmt.fmt("/home/lil/work", "/home/lil/work/fido.txt", "/home/lil/work/spot.txt"), "./fido.txt")
  end)

  test({ "does not expand $HOME / env in inputs" }, function()
    -- $HOME should be left literal; without expansion it can't match HOME-prefix.
    T.eq(path_fmt.fmt("/home/lil/work", "$HOME/spot.txt"), "$HOME/spot.txt")
  end)

  test({ "windows: backslash output for paths under cwd" }, function()
    T.eq(path_fmt.fmt([[C:\Users\Lil\work]], [[C:\Users\Lil\work\spot.txt]], nil, true), [[.\spot.txt]])
    T.eq(path_fmt.fmt([[C:\Users\Lil\work]], [[C:\Users\Lil\work\sub\fido.lua]], nil, true), [[.\sub\fido.lua]])
  end)

  test({ "windows: mixed separators normalize before prefix match" }, function()
    T.eq(path_fmt.fmt([[C:/Users/Lil/work]], [[C:\Users\Lil\work\spot.txt]], nil, true), [[.\spot.txt]])
  end)

  test({ "windows: absolute when outside cwd and HOME" }, function()
    T.eq(path_fmt.fmt([[C:\Users\Lil\work]], [[D:\elsewhere\fido.txt]], nil, true), [[D:\elsewhere\fido.txt]])
  end)
end)
