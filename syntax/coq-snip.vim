if exists('b:current_syntax')
  finish
endif


let b:current_syntax = expand('<sfile>:t:r')
echom b:current_syntax
