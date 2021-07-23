nnoremap <silent> Q  <esc>
nnoremap <silent> QQ <cmd>quitall!<cr>
vnoremap <silent> Q  <nop>
vnoremap <silent> QQ <cmd>quitall!<cr>

filetype on
set nomodeline
set secure
set termguicolors
set shortmess+=I


call plug#begin('~/.config/nvim/plugged')
Plug 'ms-jpq/coq_nvim', {'branch': 'coq'}
call plug#end()


let g:python3_host_prog = '/usr/bin/python3'
let mapleader=' '
nnoremap <leader>z <cmd>COQnow<cr>

