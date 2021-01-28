function KoKon_exit(_, code, __)
  call luaeval('KoK.on_exit(...)', [a:code])
endfunction
function KoKon_stdout(_, msg, __)
  call luaeval('KoK.on_stdout(...)', [a:msg])
endfunction
function KoKon_stderr(_, msg, __)
  call luaeval('KoK.on_stderr(...)', [a:msg])
endfunction

let s:top_level = resolve(expand('<sfile>:p:h:h'))
call luaeval('require("kok")(...)', [s:top_level])