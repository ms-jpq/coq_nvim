if exists('b:current_syntax')
  finish
endif


syntax match Error              '\v^.+$'
syntax match Comment            '\v^\#.*$'


syntax match Include            '\v^extends\s'


syntax match Keyword            '\v^snippet\s'
syntax match Error              '\v(^snippet\s\s*[^\s]+)@<=\s+.+$'
syntax match Keyword            '\v^alias\s'
syntax match Label              '\v^abbr\s'


syntax match String             '\v^\s+.*$'                             contains=Special,csTrailingWS
syntax match csTrailingWS       '\v\s+$'

syntax region Special           start="\V${" end="\V}"        contained contains=Number,Macro,Operator,csContainedString
syntax match  Special           '\v\$\d+'                     contained contains=Number

syntax match  Macro             '\v(\$\{)@<=[^\d]{-1,}(\:)@=' contained                                                  nextgroup=Operator
syntax match  Number            '\v\d+'                       contained
syntax match  Operator          '\V:'                         contained                                                  nextgroup=csContainedString
syntax match  csContainedString '\v(\:)@<=.{-1,}(\})@='       contained contains=Special


highlight default link csTrailingWS Error
highlight default link csContainedString String


let b:current_syntax = expand('<sfile>:t:r')
