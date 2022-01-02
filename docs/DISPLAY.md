# Display

### coq_settings.display

#### `coq_settings.display.mark_highlight_group`

The highlight group alias for snippet regions that you can navigate around using a hotkey.

**default:**

```json
"Pmenu"
```

---

#### coq_settings.display.ghost_text

The virtual text previewing selected completion

##### `coq_settings.display.ghost_text.enabled`

**default:**

```json
true
```

##### `coq_settings.display.ghost_text.context`

Surrounding decoration around ghost text

```json
[" 〈 ", " 〉"]
```

##### `coq_settings.display.ghost_text.highlight_group`

Ghost text colours

```json
Comment
```

---

#### coq_settings.display.pum

Vim calls the completion popup menu _`pum`_.

##### `coq_settings.display.pum.fast_close`

The popup menu will be closed on each keystroke, and re-opened when results coming in.

Disabling this will lead to more smooth menu animation, but also the stale results will be shown until the new one comes in.

**default:**

```json
True
```

##### `coq_settings.display.pum.y_max_len`

Maximum height of the popup menu.

The min of `(y_max_len, y_ratio)` wins.

**default:**

```json
16
```

##### `coq_settings.display.pum.y_ratio`

Maximum height of the popup menu, as a ratio of window height.

**default:**

```json
0.3
```

##### `coq_settings.display.pum.x_max_len`

Maximum width of the popup menu.

**default:**

```json
66
```

##### `coq_settings.display.pum.x_truncate_len`

Omit `<kind>` for snippets when we are out of space.

**default:**

```json
12
```

##### `coq_settings.display.pum.ellipsis`

Show `...` when we are out of space.

**default:**

```json
"…"
```

##### `coq_settings.display.pum.kind_context`

For item `<kind>` show `[<kind>]`, purely for aesthetics.

**default:**

```json
[" [", "]"]
```

##### `coq_settings.display.pum.source_context`

For item `<source>` show `「<source>」`, purely for aesthetics.

**default:**

```json
["「", "」"]
```

---

#### coq_settings.display.preview

Used for the preview window.

##### `coq_settings.display.preview.x_max_len`

Maximum width.

**default:**

```json
88
```

##### `coq_settings.display.preview.resolve_timeout`

Bit niche, if a completion has documentation, but still be be looked up for further documentation, how long to wait for further documentation to show up.

**default:**

```json
0.09
```

##### `coq_settings.display.preview.border`

The border of the preview window.

It can be several values: one of `"single", "double", "rounded", "solid", "shadow"`

Or an 8 tuple of `char`, see `:help nvim_open_win()` for details

Or an 8 tuple of `[<char>, <highlight group>]`

To make it look like Neovim builtin hover window, use:

```json
[
  ["", "NormalFloat"],
  ["", "NormalFloat"],
  ["", "NormalFloat"],
  [" ", "NormalFloat"],
  ["", "NormalFloat"],
  ["", "NormalFloat"],
  ["", "NormalFloat"],
  [" ", "NormalFloat"]
]
```

**default:**

```json
"rounded"
```

##### `coq_settings.display.preview.positions`

Preferred ordering of preview window.

This is a tie breaker, previews will be shown in the position with most usable-space first.

If you do not like a position, setting it to `null` will disable it entirely.

Setting everything to `null` will disable previews.

**default:**

```json
{ "north": 1, "south": 2, "west": 3, "east": 4 }
```

---

#### coq_settings.display.icons

To see icons, you need to install a [supported font](https://www.nerdfonts.com/#home).

See [cheat sheet](https://www.nerdfonts.com/cheat-sheet) for list of icons.

See [config/defaults.yml](https://github.com/ms-jpq/coq_nvim/blob/coq/config/defaults.yml) for defaults.

##### `coq_settings.display.icons.mode`

One of: `none`, `short`, `long`

- none : show text only

- short: show icons only

- long: show icons + text

**default:**

```json
"long"
```

##### `coq_settings.display.icons.spacing`

How many ` ` of padding to use after icon.

Increase this if your icons are too close to each other.

**default:**

```json
1
```

##### `coq_settings.display.icons.aliases`

Alias for mappings

`<from_*>` gets the same icon as `<to_*>`

```json
{ "<from_1>": "<to_1>", "<from_2>": "<to_2>" }
```

ie. `{ "EnumMember": "Enum" }`, makes `EnumMember` have the same icon as `Enum`

##### `coq_settings.display.icons.mappings`

`<kind_*>` gets mapped to `<icon_*>`

```json
{ "<kind_1>": "<icon_1>", "<kind_2>": "<icon_2>" }
```

ie. `{ "Keyword": "🔑", "Constructor": "👷" }`

For a (mostly exhaustive) list of `kind` keys: `:lua print(vim.inspect(vim.lsp.protocol.CompletionItemKind))`

For `ctags` do `ctags --list-kinds-full`.

The defaults do not cover `ctags`, as there are too many to find unique icons for.
