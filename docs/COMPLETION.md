# Completion

### coq_settings.completion

#### coq_settings.completion.always

Always trigger completion on keystroke

**default:**

```json
true
```

---

#### coq_settings.completion.sticky_manual

Trigger completion on every keystroke after manual completion until you leave insert mode.

**default:**

```json
true
```

---

#### coq_settings.completion.skip_after

Set of tokens that should prevent auto completion, when found directly before the cursor.

ie `["{", "}", "[", "]"]`, etc

Setting this to `[""]` will disable auto complete.

**default:**

```json
[]
```
