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

##### `coq_settings.clients.<x>.weight_adjust`

Weight adjustment for ranking, normalized to `[0.5, 1.5]` using `S(x) = 1 / (1 + e^-x) + 0.5` (bigger weight -> sorted higher up)

Ideally pick a number between `[-2, 2]`.

`S(0) = 1` no adjustment

`S(-2) ~= 0.6` anything smaller has diminishing returns

`S(+2) ~= 1.4` anything bigger has diminishing returns

**default:**

```json
<preset float>
```

---

#### coq_settings.clients.lsp

##### `coq_settings.clients.lsp.resolve_timeout`

Time it takes to wait for LSP servers to respond with header import before edit is applied.

**default:**

```json
0.06
```

---

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

---

#### coq_settings.clients.snippets

##### `coq_settings.clients.snippets.user_path`

Additional snippet load path, if relative, resolves under nvim config dir.

**default:**

```json
null
```

##### `coq_settings.clients.snippets.warn`

List of things to issue an warning about.

Default is to nag about out of date snippets.

**default:**

```json
["outdated"]
```

---

#### coq_settings.clients.paths

##### `coq_settings.clients.paths.resolution`

For relative paths, what should their potential base path(s) be.

- `cwd`: current working directory

- `file`: the current file's parent directory

**default:**

```json
["cwd", "file"]
```

##### `coq_settings.clients.paths.path_seps`

Which separator chars to use. Empty for default. Must be `/` under unix and `/` or `\` for windows.

**default:**

```json
[]
```

##### `coq_settings.clients.paths.preview_lines`

Try to preview this many lines.

**default:**

```json
6
```

---

#### coq_settings.clients.tree_sitter

##### `coq_settings.clients.tree_sitter.search_context`

Only query this many lines about the cursor

**default:**

```json
333
```

##### `coq_settings.clients.tree_sitter.slow_threshold`

Send out a warning if treesitter is slower than this

**default:**

```json
0.1
```

##### `coq_settings.clients.tree_sitter.path_sep`

Aesthetics only, path separator.

**default:**

```json
" ⇊"
```

---

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

---

#### coq_settings.clients.tmux

##### `coq_settings.clients.tmux.match_syms`

Also match symbols in addition to words.

**default:**

```json
false
```

---

#### coq_settings.clients.tabnine

No special conf.

But _Disabled by default_. Need `coq_settings.clients.tabnine=true` to enable.
