let s:top_level = resolve(expand('<sfile>:p:h:h'))

function s:COQnoop()
  0
endfunction
command! COQnoop call s:COQnoop()

call luaeval('require("coq")(...)', [s:top_level])

