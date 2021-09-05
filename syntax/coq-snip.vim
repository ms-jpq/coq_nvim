if exists('b:current_syntax')
  finish
endif


syntax match Error       '^.*$'
syntax match Comment     '\v^\#.*$'


syntax match Include     '\v^extends\s'
"syntax match Delimiter   '\v([^,]*)@<=\,' contained


syntax match Keyword     '\v^snippet\s'
syntax match Error       '\v(^snippet\s[^s]+\s+)@<=.*$'
syntax match Keyword     '\v^alias\s'
syntax match Label       '\v^abbr\s'


syntax match String      '\v^\s+.*$' contains=Special
syntax match Special     '\v\$\{[^\}]+\}' contained contains=Number,Conditional
syntax match Number      '\v\d+'
syntax match Conditional '\V:'


let b:current_syntax = expand('<sfile>:t:r')
