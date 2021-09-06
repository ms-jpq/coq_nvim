if exists('b:current_syntax')
  finish
endif


syntax match Error       '\v^.+$'
syntax match Error       '\v\s+$'
syntax match Comment     '\v^\#.*$'


syntax match Include     '\v^extends\s'


syntax match Keyword     '\v^snippet\s'
syntax match Error       '\v(^snippet\s\s*[^\s]+)@<=\s+.+$'
syntax match Keyword     '\v^alias\s'
syntax match Label       '\v^abbr\s'


syntax match String      '\v^\s+.*$' contains=Special
syntax match Special     '\v\$\{[^\}]+\}' contained contains=Number,Conditional
syntax match Number      '\v\d+' contained
syntax match Conditional '\V:' contained


let b:current_syntax = expand('<sfile>:t:r')
