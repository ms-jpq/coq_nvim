local T = require "coq.lib.test"
local parse = require "coq.producers.fullpaths.parse"

T.describe({ "fullpaths.parse separators" }, function(test)
  for _, case in pairs {
    { false, "kennel/lil/toy", "kennel/lil/toy", "/" },
    { false, [[kennel\lil/toy]], [[kennel\lil/toy]], "/" },
    { true, "lil", "lil", [[\]] },
    { true, "kennel/lil/toy", "kennel/lil/toy", "/" },
    { true, [[kennel\lil\toy]], [[kennel\lil\toy]], [[\]] },
    { true, [[kennel/lil\toy]], [[kennel/lil\toy]], [[\]] },
    { true, [[kennel\lil/toy]], [[kennel\lil/toy]], "/" },
  } do
    local is_windows, input, partial, sep = unpack(case)
    ---@cast is_windows boolean
    ---@cast input string
    test({ tostring(is_windows), input }, function()
      T.eq(parse.candidate("see @" .. input, { symbol = "@", is_windows = is_windows }), {
        start = 4,
        partial = partial,
        local_sep = sep,
      })
    end)
  end
end)
