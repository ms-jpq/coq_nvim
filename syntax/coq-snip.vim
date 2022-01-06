if exists('b:current_syntax')
  finish
endif


syntax match  Error   /\v^.+$/
syntax match  Comment /\v^\#.*$/


syntax match  Include /\v^extends\s/
syntax match  Keyword /\v^snippet\s/
syntax match  Error   /\v(^snippet\s\s*[^\s]+)@<=\s+.+$/
syntax match  Keyword /\v^alias\s/
syntax match  Label   /\v^abbr\s/


syntax match  csBody       /\v^\s+.*$/ contains=csEscape,csTrailingWS,csTabstop,csVariable,csChoice,csPlaceHolder
syntax match  csEscape     /\V$$/
syntax match  csTrailingWS /\v\s+$/


syntax match  csTabstop       /\v\$\d+/      contained contains=csTabstopDollar,csTabstopNumber
syntax match  csTabstopDollar /\v\$(\d+)@=/  contained
syntax match  csTabstopNumber /\v(\$)@<=\d+/ contained


syntax match  csVariable        /\v\$\{(\w+|\w+\:\w+)\}/ contained contains=csVariableScopeL,csVariableScopeR,csVariableSep,csVariableName,csVariableDefault
syntax match  csVariableScopeL  /\v\$\{(\w+)@=/          contained
syntax match  csVariableScopeR  /\v(\w+)@<=\}/           contained
syntax match  csVariableSep     /\v(\w+)@<=\:(\w+)@=/    contained
syntax match  csVariableName    /\v(\$\{)@<=\w+/         contained
syntax match  csVariableDefault /\v\w+(\})@=/            contained


"syntax match  csChoice   /\$\{\|\/



"syntax match  csSpecial  /\V$/   contained nextgroup=Number
"syntax match  Number     /\v(\$\{?)@<=\d+/ contained


"syntax region Special     start=/\V${/    end=/\V}/        contained contains=Special,Number,Conditional,csString,csTrailingWS
"syntax match  Conditional /\v(\$\{?\d+)@<=\:/              contained

"syntax match  csString    start=/\v(\$\{?\d+\:)@<=.+/  end=/\v.+(})@=/  contained contains=Special,Number,csEscString,csTrailingWS


highlight default link csBody          String
highlight default link csEscape        String
highlight default link csTrailingWS    Error

highlight default link csTabstopDollar Special
highlight default link csTabstopNumber Number

highlight default link csVariableScopeL  Special
highlight default link csVariableScopeR  Special
highlight default link csVariableSep     Conditional
highlight default link csVariableName    Label
highlight default link csVariableDefault String




let b:current_syntax = expand('<sfile>:t:r')
