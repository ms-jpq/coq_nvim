# Conf

All configurations are under the global variable **`coq_settings`**.

VimL:

```vim
let g:coq_settings = { ... }
```

Lua:

```lua
local vim.g.coq_settings = { ... }
```

---

## Shorthand

Dictionary keys will be automatically expanded with the `.` notation. This works recursively.

ie. The following are equivalent

```json
{ "dog.puppy": 2 }
```

```json
{ "dog": { "puppy": 2 } }
```

Note in lua, you will need to quote your keys like so:

```lua
{ ["dog.puppy"] = 2 }
```

Note in VimL, to specify `True` and `False`, you need to use the following:

```vim
v:true
v:false
```

---

## Validation

Variables will be validated against a schema.

ie.

```vim
let g:coq_settings = { 'match.dog': 'scratch, stratch' }
```

Will give you the following error message:

![schema error.png](https://github.com/ms-jpq/chadtree/raw/chad/docs/img/schema_error.png)

**Notice it says `Extra keys: {dog}`**

---

## Specifics

### coq_settings.keymap

See help docs on [keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

### coq_settings.match

#### `coq_settings.match.unifying_chars`

#### `coq_settings.match.max_results`

#### `coq_settings.match.context_lines`

#### `coq_settings.match.exact_matches`

#### `coq_settings.match.look_ahead`

#### `coq_settings.match.fuzzy_cutoff`

### coq_settings.limits

#### `coq_settings.limits.max_buf_index`

#### `coq_settings.limits.idle_time`

#### `coq_settings.limits.timeout`

#### `coq_settings.limits.manual_timeout`

### coq_settings.weights

#### `coq_settings.weights.prefix_matches`

#### `coq_settings.weights.edit_distance`

#### `coq_settings.weights.insertion_order`

#### `coq_settings.weights.neighbours`

### coq_settings.display

#### coq_settings.display.pum

##### `coq_settings.display.pum.y_max_len`

##### `coq_settings.display.pum.y_ratio`

##### `coq_settings.display.pum.x_max_len`

##### `coq_settings.display.pum.x_min_len`

##### `coq_settings.display.pum.ellipsis`

##### `coq_settings.display.pum.kind_context`

##### `coq_settings.display.pum.source_context`

#### coq_settings.display.preview

##### `coq_settings.display.preview`

##### `coq_settings.display.preview.y_margin`

##### `coq_settings.display.preview.x_margin`

##### `coq_settings.display.preview.x_max_len`

##### `coq_settings.display.preview.x_max_len`

##### `coq_settings.display.preview.lsp_timeout`

##### `coq_settings.display.preview.positions`

#### `coq_settings.display.mark_highlight_group`

### coq_settings.clients

#### `coq_settings.clients.lsp`

#### `coq_settings.clients.tags`

#### `coq_settings.clients.snippets`

#### `coq_settings.clients.paths`

#### `coq_settings.clients.tree_sitter`

#### `coq_settings.clients.buffers`

#### `coq_settings.clients.tmux`

#### `coq_settings.clients.tabnine`

