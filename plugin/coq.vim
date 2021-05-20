let s:top_level = resolve(expand('<sfile>:p:h'))

call luaeval('require("coq")(...)', [s:top_level])
