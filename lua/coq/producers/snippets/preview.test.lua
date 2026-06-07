local T = require "coq.lib.test"
local preview = require "coq.producers.snippets.preview"

T.describe({ "snippets.preview" }, function(test)
  test({ "placeholder shown as default text" }, function()
    T.eq(preview.preview "fido(${1:bone})", "fido(bone)")
  end)

  test({ "bare tabstop renders as empty" }, function()
    T.eq(preview.preview "fido($1)", "fido()")
  end)

  test({ "${VAR:default} renders the default" }, function()
    T.eq(preview.preview "${NAME:fido}", "fido")
  end)

  test({ "choice ${1|a,b,c|} renders first option" }, function()
    T.eq(preview.preview "${1|sit,stay,roll|}", "sit")
  end)

  test({ "escaped dollar comes through literal" }, function()
    T.eq(preview.preview [[\$1]], "$1")
  end)
end)
