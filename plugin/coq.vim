let s:top_level = resolve(expand('<sfile>:p:h:h'))

call luaeval('require("coq")(...)', [s:top_level])
