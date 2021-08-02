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

### coq_settings.limits

#### `coq_settings.limits.index_cutoff`

#### `coq_settings.limits.idle_timeout`

#### `coq_settings.limits.timeout`

#### `coq_settings.limits.manual_timeout`
