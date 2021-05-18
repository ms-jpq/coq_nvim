function Coqon_exit(_, code, __)
  call luaeval('Coq.on_exit(...)', [a:code])
endfunction
function Coqon_stdout(_, msg, __)
  call luaeval('Coq.on_stdout(...)', [a:msg])
endfunction
function Coqon_stderr(_, msg, __)
  call luaeval('Coq.on_stderr(...)', [a:msg])
endfunction

let s:top_level = resolve(expand('<sfile>:p:h:h'))
call luaeval('require("Coq")(...)', [s:top_level])
