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
let g:coq_settings = { 'match.look_ahead': 'dog' }
```

Will give you the following error message:

![conf_demo.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/conf.png)

**Notice it says `Extra keys: {dog}`**

---

## Specifics

Set `coq_settings.auto_start` to `true | 'shut-up'` to auto start.

Set `coq_settings.xdg` to `true` to use `XDG`.

- [:COQhelp keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

Key bindings

- [:COQhelp fuzzy](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

Fuzzy ranking

- [:COQhelp display](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

Appearances

- [:COQhelp sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SOURCES.md)

Source specific

- [:COQhelp misc](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/MISC.md)

Misc (including timeouts)
