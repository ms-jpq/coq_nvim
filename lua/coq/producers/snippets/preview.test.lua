local T = require "coq.lib.test"
local preview = require "coq.producers.snippets.preview"

T.describe({ "snippets.preview" }, function(test)
  test({ "placeholder default wrapped in guillemets" }, function()
    T.eq(preview.preview "fido(${1:bone})", "fido(‹bone›)")
  end)

  test({ "bare tabstop renders as empty guillemets" }, function()
    T.eq(preview.preview "fido($1)", "fido(‹›)")
  end)

  test({ "${VAR:default} wraps the default" }, function()
    T.eq(preview.preview "${NAME:fido}", "‹fido›")
  end)

  test({ "choice ${1|a,b,c|} wraps the first option" }, function()
    T.eq(preview.preview "${1|sit,stay,roll|}", "‹sit›")
  end)

  test({ "escaped dollar comes through literal" }, function()
    T.eq(preview.preview [[\$1]], "$1")
  end)
end)
