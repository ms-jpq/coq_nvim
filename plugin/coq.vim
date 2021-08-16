let s:top_level = resolve(expand('<sfile>:p:h:h'))

function COQnoop()
  0
endfunction
command! COQnoop call COQnoop()

call luaeval('require("coq")(...)', [s:top_level])

