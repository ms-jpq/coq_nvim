local T = require "coq.lib.test"
local txt = require "coq.lib.text"

local drain = function(iter)
  local out = {}
  for v in iter do
    table.insert(out, v)
  end
  return out
end

T.describe("text.splitlines", function(test)
  test("yields a single line for a separator-free string", function()
    T.eq(drain(txt.splitlines "labrador"), { "labrador" })
  end)

  test("splits on LF", function()
    T.eq(drain(txt.splitlines "lil\nspot\nfido"), { "lil", "spot", "fido" })
  end)

  test("splits on CRLF as one separator", function()
    T.eq(drain(txt.splitlines "lil\r\nspot\r\nfido"), { "lil", "spot", "fido" })
  end)

  test("splits on bare CR", function()
    T.eq(drain(txt.splitlines "lil\rspot\rfido"), { "lil", "spot", "fido" })
  end)

  test("mixes line endings in one input", function()
    T.eq(drain(txt.splitlines "a\nb\r\nc\rd"), { "a", "b", "c", "d" })
  end)

  test("a trailing separator yields a final empty line", function()
    T.eq(drain(txt.splitlines "lil\n"), { "lil", "" })
    T.eq(drain(txt.splitlines "lil\r\n"), { "lil", "" })
    T.eq(drain(txt.splitlines "lil\r"), { "lil", "" })
  end)

  test("empty input yields one empty line", function()
    T.eq(drain(txt.splitlines ""), { "" })
  end)

  test("consecutive separators yield empty lines between them", function()
    T.eq(drain(txt.splitlines "a\n\nb"), { "a", "", "b" })
    T.eq(drain(txt.splitlines "a\r\n\r\nb"), { "a", "", "b" })
  end)

  test("iter is idempotent on nil — calls past end stay nil", function()
    local iter = txt.splitlines "lil"
    T.eq(iter(), "lil")
    T.eq(iter(), nil)
    T.eq(iter(), nil)
  end)
end)

T.describe("text.is_multiline", function(test)
  test("flat strings are not multiline", function()
    T.eq(txt.is_multiline "labrador", false)
    T.eq(txt.is_multiline "", false)
  end)

  test("LF, CR, or CRLF all count", function()
    T.eq(txt.is_multiline "lil\nspot", true)
    T.eq(txt.is_multiline "lil\rspot", true)
    T.eq(txt.is_multiline "lil\r\nspot", true)
  end)

  test("a trailing separator alone counts", function()
    T.eq(txt.is_multiline "lil\n", true)
  end)
end)
