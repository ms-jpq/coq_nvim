# Sources

### coq_settings.clients

##### `coq_settings.clients.<x>.enabled`

Enable source

**default:**

```json
true
```

except for `tabnine`

##### `coq_settings.clients.<x>.short_name`

Source name to display in the completion menu.

**Must be unique**

**default:**

```json
<name>
```

##### `coq_settings.clients.<x>.tie_breaker`

Tie breaker for ranking.

This is fairly low on the rank algorithm. It will usually not take effect.

**Must be unique**

**default:**

```json
<name>
```

---

#### coq_settings.clients.lsp

#### `coq_settings.clients.lsp.resolve_timeout`

Time it takes to wait for LSP servers to respond with header import before edit is applied.

**default:**

```json
0.06
```

#### coq_settings.clients.tags

##### `coq_settings.clients.tags.parent_scope`

Aesthetics only, parent indicator.

**default:**

```json
" ⇊"
```

##### `coq_settings.clients.tags.path_sep`

Aesthetics only, path separator.

**default:**

```json
" ⇉ "
```

#### coq_settings.clients.snippets

##### `coq_settings.clients.snippets.sources`

Which snippets to load. When empty, load all snippets.

Take a look at [compilation.yml](https://github.com/ms-jpq/coq_nvim/blob/coq/config/compilation.yml) under `paths.<x>.[<names>]`, the `[<names>]` are the keys.

**default:**

```json
[]
```

#### coq_settings.clients.paths

##### `coq_settings.clients.paths.preview_lines`

Try to preview this many lines.

**default:**

```json
6
```

#### coq_settings.clients.tree_sitter

No special conf.

#### coq_settings.clients.buffers

##### `coq_settings.clients.buffers.match_syms`

Also match symbols in addition to words.

**default:**

```json
false
```

##### `coq_settings.clients.buffers.same_filetype`

Restrict matching to buffers of the same filetype

**default:**

```json
false
```

#### coq_settings.clients.tmux

##### `coq_settings.clients.tmux.match_syms`

Also match symbols in addition to words.

**default:**

```json
false
```

#### coq_settings.clients.tabnine

No special conf.

But _Disabled by default_. Need `coq_settings.clients.tabnine=true` to enable.
