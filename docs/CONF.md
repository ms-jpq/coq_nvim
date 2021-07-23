# Conf

All configurations are under the global variable **`chadtree_settings`**.

VimL:

```vim
let g:chadtree_settings = { ... }
```

Lua:

```lua
local chadtree_settings = { ... }
vim.api.nvim_set_var("chadtree_settings", chadtree_settings)
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
let g:chadtree_settings = { 'ignore.dog': 'scratch, stratch' }
```

Will give you the following error message:

![schema error.png](https://github.com/ms-jpq/chadtree/raw/chad/docs/img/schema_error.png)

**Notice it says `Extra keys: {dog}`**

---

## Specifics

### Match

### Limits

### Weights

### Keymap

### Display

### Clients

#### LSP

#### Tags

#### Snippets

#### Paths

#### TreeSitter

#### Buffers

#### Tmux

#### Tabnine

