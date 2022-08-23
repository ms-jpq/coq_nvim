if exists('b:current_syntax')
  finish
endif


syntax match Error        '\v^.+$'
syntax match Comment      '\v^\#.*$'


syntax match Include      '\v^extends\s'


syntax match Keyword      '\v^snippet\s'
syntax match Error        '\v(^snippet\s\s*[^\s]+)@<=\s+.+$'
syntax match Keyword      '\v^alias\s'
syntax match Label        '\v^abbr\s'


syntax match String            '\v^\s+.*$'                        contains=Special,csTrailingWS
syntax match csTrailingWS      '\v\s+$'

syntax match Special           '\v\$\{.{-1,}\}|(\$\d+)' contained contains=Number,Conditional,csContainedString
syntax match Number            '\v\d+'                  contained
syntax match Conditional       '\V:'                    contained nextgroup=csContainedString
syntax match csContainedString '\v(\:)@<=.{-1,}(\})@='  contained contains=Special


highlight default link csTrailingWS Error
highlight default link csContainedString String


let b:current_syntax = expand('<sfile>:t:r')
