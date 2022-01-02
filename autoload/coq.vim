function! s:filter_completions(arg_lead, completions) abort
  let l:lead = escape(a:arg_lead, '\\')
  return filter(a:completions, {_, val -> val =~# "^" . l:lead})
endfunction

function! coq#complete_now(arg_lead, cmd_line, cursor_pos) abort
  let l:args = [
        \ '-s',
        \ '--shut-up',
        \ ]

  return s:filter_completions(a:arg_lead, l:args)
endfunction

function! coq#complete_snips(arg_lead, cmd_line, cursor_pos) abort
  let l:args = [
        \ 'ls',
        \ 'cd',
        \ 'compile',
        \ 'edit',
        \ ]

  return s:filter_completions(a:arg_lead, l:args)
endfunction

function! coq#complete_help(arg_lead, cmd_line, cursor_pos) abort
  let l:topics = [
        \ 'index',
        \ 'config',
        \ 'keybind',
        \ 'snips',
        \ 'fuzzy',
        \ 'comp',
        \ 'display',
        \ 'sources',
        \ 'misc',
        \ 'stats',
        \ 'perf',
        \ 'custom_sources',
        \ ]

  if a:cmd_line[a:cursor_pos - 7 : a:cursor_pos] ==# ' --web '
    return s:filter_completions(a:arg_lead, l:topics)
  endif

  return s:filter_completions(a:arg_lead, insert(l:topics, '--web'))
endfunction

