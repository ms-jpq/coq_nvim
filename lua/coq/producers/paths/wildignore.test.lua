local T = require "coq.lib.test"
local wildignore = require "coq.producers.paths.wildignore"

T.describe("wildignore.glob_to_lua", function(test)
  test("* matches any sequence", function()
    T.eq(wildignore.glob_to_lua "*.o", "^.*%.o$")
  end)

  test("? matches a single char", function()
    T.eq(wildignore.glob_to_lua "?.lua", "^.%.lua$")
  end)

  test("escapes regex metacharacters", function()
    T.eq(wildignore.glob_to_lua "(x).+", "^%(x%)%.%+$")
  end)

  test("anchors both ends", function()
    local p = wildignore.glob_to_lua "fido"
    T.eq(p, "^fido$")
  end)
end)

T.describe("wildignore.compile", function(test)
  test("empty string yields no patterns", function()
    T.eq(wildignore.compile "", {})
  end)

  test("comma-splits entries", function()
    T.eq(wildignore.compile "*.o,*.tmp", { "^.*%.o$", "^.*%.tmp$" })
  end)

  test("skips empty entries from trailing commas", function()
    T.eq(wildignore.compile "*.o,,*.tmp", { "^.*%.o$", "^.*%.tmp$" })
  end)
end)

T.describe("wildignore.is_ignored", function(test)
  local pats = wildignore.compile "*.o,*/node_modules/*"

  test("matches basename pattern (*.o vs fido.o)", function()
    T.eq(wildignore.is_ignored(pats, "fido.o", "/var/dogs/fido.o"), true)
  end)

  test("matches full-path pattern (*/node_modules/*)", function()
    T.eq(wildignore.is_ignored(pats, "react.js", "/var/dogs/node_modules/react.js"), true)
  end)

  test("does not match plain filename when pattern requires structure", function()
    T.eq(wildignore.is_ignored(pats, "fido.txt", "/var/dogs/fido.txt"), false)
  end)

  test("empty pattern list never matches", function()
    T.eq(wildignore.is_ignored({}, "fido.o", "/var/dogs/fido.o"), false)
  end)

  test("? wildcard is single-character", function()
    local single = wildignore.compile "?.o"
    T.eq(wildignore.is_ignored(single, "a.o", "/a.o"), true)
    T.eq(wildignore.is_ignored(single, "ab.o", "/ab.o"), false)
  end)
end)

T.describe("wildignore vs vim.fn.glob2regpat parity", function(test)
  ---@param glob string
  ---@param name string
  ---@param full string
  ---@return boolean
  local vim_matches = function(glob, name, full)
    local re = vim.regex(vim.fn.glob2regpat(glob))
    return re:match_str(name) ~= nil or re:match_str(full) ~= nil
  end

  ---@param glob string
  ---@param name string
  ---@param full string
  ---@return boolean
  local our_matches = function(glob, name, full)
    return wildignore.is_ignored(wildignore.compile(glob), name, full)
  end

  ---@type [string, string, string][]
  local CASES = {
    -- Within our supported subset: literals, *, ?
    { "fido", "fido", "/var/dogs/fido" },
    { "fido", "rex", "/var/dogs/rex" },
    { "fido", "fidolicious", "/var/dogs/fidolicious" },
    { "*.o", "spot.o", "/var/dogs/spot.o" },
    { "*.o", "spot.txt", "/var/dogs/spot.txt" },
    { "*.o", "o", "/var/dogs/o" },
    { "*.tmp", "fido.tmp.bak", "/var/dogs/fido.tmp.bak" },
    { "?.lua", "x.lua", "/x.lua" },
    { "?.lua", "xy.lua", "/xy.lua" },
    { "?.lua", ".lua", "/.lua" },
    { "*/node_modules/*", "react.js", "/var/dogs/node_modules/react.js" },
    { "*/node_modules/*", "react.js", "/var/dogs/react.js" },
    { "*node_modules*", "react.js", "/var/dogs/node_modules/react.js" },
    -- Regex metacharacters in literal positions
    { "fido+", "fido+", "/var/fido+" },
    { "fido+", "fidooo", "/var/fidooo" },
    { "fido.bak", "fidoXbak", "/var/fidoXbak" },
    { "fido.bak", "fido.bak", "/var/fido.bak" },
    { "(spot)", "(spot)", "/var/(spot)" },
    { "(spot)", "spot", "/var/spot" },
  }

  for _, case in ipairs(CASES) do
    local glob, name, full = case[1], case[2], case[3]
    test(string.format("%q vs name=%q full=%q", glob, name, full), function()
      T.eq(our_matches(glob, name, full), vim_matches(glob, name, full))
    end)
  end
end)
