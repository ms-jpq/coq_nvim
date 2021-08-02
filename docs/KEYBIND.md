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
