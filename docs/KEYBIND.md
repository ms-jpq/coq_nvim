# Keybind

`coq_settings.keymap`

### coq_settings.keymap.recommended

Set up modern keybinds:

- `<esc>` -> exit to normal

- `<bs>` -> backspace always, even when completion menu is open

- `<cr>` -> used to select completion if completion menu is open

- `<tab>` -> if completion menu is open: select next item

- `<s-tab>` -> if completion menu is open: select prev item

**default:**

```json
true
```

#### `coq_settings.keymap.manual_complete`

Manually trigger completions, with a longer timeout.

**default:**

```json
"<c-space>"
```

#### `coq_settings.keymap.bigger_preview`

When floating preview window is open, move the preview from floating window to fixed window.

Useful for reading references.

**default:**

```json
"<c-k>"
```

#### `coq_settings.keymap.jump_to_mark`

When snippets come with placeholders, jump to edit next placeholder.

Will ask to apply linked edits in a menu, if linked edits are available.

Pressing `<c-c>` to resume to edit as normal.

**default:**

```json
"<c-h>"
```

# Custom keybindings

If you would like to set your own keybindings, add the following to your
init.vim and edit them to your liking.

```vim
" NOTE: You may already have these in your configuration somewhere.
" Autocomplete menu options
set completeopt=menuone,noselect,noinsert
set noshowmode
set shortmess+=c

" 🐓 Coq completion settings

" Set recommended to false
let g:coq_settings = { "keymap.recommended": v:false }

" Keybindings
ino <silent><expr> <Esc>   pumvisible() ? "\<C-e><Esc>" : "\<Esc>"
ino <silent><expr> <C-c>   pumvisible() ? "\<C-e><C-c>" : "\<C-c>"
ino <silent><expr> <BS>    pumvisible() ? "\<C-e><BS>"  : "\<BS>"
ino <silent><expr> <CR>    pumvisible() ? (complete_info().selected == -1 ? "\<C-e><CR>" : "\<C-y>") : "\<CR>"
ino <silent><expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
ino <silent><expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<BS>"
```

`coq#pumvisible()` returns `1` if a popup menu is visible and the popup menu is created by `coq`.

#
