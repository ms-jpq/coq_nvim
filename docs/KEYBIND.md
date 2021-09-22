# Keybind

`coq_settings.keymap`

### coq_settings.keymap.recommended

Set up modern keybinds:

- `<esc>` -> exit to normal

- `<bs>` -> backspace always, even when completion menu is open

- `<c-w>` -> delete word before the cursor, even when completion menu is open

- `<c-u>` -> delete all entered characters before the cursor, even when completion menu is open

- `<cr>` -> used to select completion if completion menu is open

- `<tab>` -> if completion menu is open: select next item

- `<s-tab>` -> if completion menu is open: select prev item

**default:**

```json
true
```

### coq_settings.keymap.pre_select

Always select first result. Will need to frequently hit manual exit completion with `<c-e>` if chosen.

**default:**

```json
false
```

#### `coq_settings.keymap.manual_complete`

Manually trigger completions, with a longer timeout.

**default:**

```json
"<c-space>"
```

#### `coq_settings.keymap.repeat`

Repeat last edit performed by `coq`.

Note: this is not the same as `.` key in Vim. Vim's `.` key is pretty "dumb" as it simply stores and replays keystrokes, while `coq` performs arbitrary edits.

ie. typo correction, some LSP requests, multi-line Tabnine edits, etc

`coq` does not records it's edits in `.` history, because it's not feasible to translate any arbitrary edit into a sequence of `.` keystrokes without substantial edgecases.

ie. `coq` cannot realistically reproduce Vim's "unique" interpertion of unicode grapheme clusters bug for bug.

**default:**

```json
null
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

#### `coq_settings.keymap.eval_snips`

Evaluate current visual selection or buffer as user defined snippets.

**default:**

```json
null
```

## Custom keybindings

If you would like to set your own keybindings, add the following to your
init.vim and edit them to your liking.

```vim
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
