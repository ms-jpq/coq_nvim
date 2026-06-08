# Conf

All configurations are under the global variable **`coq_settings`**.

VimL:

```vim
let g:coq_settings = { ... }
```

Lua:

```lua
vim.g.coq_settings = { ... }
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

Vim:

```vim
let g:coq_settings = { 'match.fuzzy_cutoff': 'dog' }
```

Lua:

```lua
vim.g.coq_settings = {
    match = {
        fuzzy_cutoff = "dog",
    },
}
```

Will give you the following error message:

![conf_demo.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/conf.png)

**Notice it says `Extra keys: {dog}`**

---

## Specifics

v2 attaches on `setup()` — there is no `auto_start` or `xdg` option. See [v2](./v2.md).

- [:COQ help keybind](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/KEYBIND.md)

Key bindings

- [:COQ help fuzzy](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

Fuzzy ranking

- [:COQ help comp](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/COMPLETION.md)

Completion options

- [:COQ help display](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/DISPLAY.md)

Appearances

- [:COQ help sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/SOURCES.md)

Source specific

- [:COQ help misc](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/MISC.md)

Misc (including timeouts)
