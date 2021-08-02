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

#### coq_settings.clients.tags

##### `coq_settings.clients.tags.path_sep`

##### `coq_settings.clients.tags.parent_scope`

#### coq_settings.clients.snippets

##### `coq_settings.clients.snippets.sources`

#### coq_settings.clients.paths

#### coq_settings.clients.tree_sitter

#### coq_settings.clients.buffers

##### `coq_settings.clients.buffers.match_syms`

##### `coq_settings.clients.buffers.same_filetype`

#### coq_settings.clients.tmux

##### `coq_settings.clients.tmux.match_syms`

#### coq_settings.clients.tabnine
