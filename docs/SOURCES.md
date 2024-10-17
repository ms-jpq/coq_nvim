# Sources

### coq_settings.clients

##### `coq_settings.clients.<x>.enabled`

Enable source

**default:**

```json
true
```

except for `tabnine` and `lsp_inline`

##### `coq_settings.clients.<x>.short_name`

Source name to display in the completion menu.

**Must be unique**

**default:**

```json
<name>
```

##### `coq_settings.clients.<x>.weight_adjust`

Weight adjustment for ranking, normalized to `[0.5, 1.5]` using `S(x) = 1 / (1 + e^-x) + 0.5` (bigger weight -> sorted higher up)

`S(0) = 1` no adjustment

`S(-2) ~= 0.6` anything smaller has diminishing returns

`S(+2) ~= 1.4` anything bigger has diminishing returns

**[default:](https://github.com/ms-jpq/coq_nvim/blob/coq/config/defaults.yml)**

```json
<preset float>
```

##### `coq_settings.clients.<x>.always_on_top`

Alright you guys keep asking this:

This setting will override all ranking metrics and keep the source always on top.

For sources other than `LSP` and `third_party`, the config is a boolean value.

**default**

```json
false
```

For `LSP` and `third_party`, the config is either `null` or `["<lsp/client_name_1>", "<lsp/client_name_2>", ...]`.

The empty `[]` will keep all clients on top regardless of lsp client names.

**default**

```json
null
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
["missing", "outdated"]
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

#### coq_settings.clients.registers

##### `coq_settings.clients.registers.match_syms`

Also match symbols in addition to words.

**default:**

```json
false
```

##### `coq_settings.clients.registers.max_yank_size`

For the yank register: `0`. Ignore contents if size exceeds limit.

**default:**

```json
8888
```

##### `coq_settings.clients.registers.words`

Complete from contents of registers.

`0` is the "last yank" register.

Can also take in named registers `a-z`.

**default:**

```json
["0"]
```

##### `coq_settings.clients.registers.lines`

Complete lines from contents of registers `a-z`.

Will only match at beginning of lines.

**default:**

```json
[]
```

---

#### coq_settings.clients.tmux

##### `coq_settings.clients.tmux.match_syms`

Also match symbols in addition to words.

**default:**

```json
false
```

##### `coq_settings.clients.tmux.all_sessions`

Pull words & symbols from not just current session.

**default:**

```json
true
```

---

#### coq_settings.clients.tabnine

No special conf.

But _Disabled by default_. Need `coq_settings.clients.tabnine=true` to enable.

---

#### coq_settings.clients.third_party

No special conf.

See [:COQhelp custom_sources](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/CUSTOM_SOURCES.md)
