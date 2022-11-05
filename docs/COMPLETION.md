# Completion

### coq_settings.completion

#### coq_settings.completion.always

Always trigger completion on keystroke

**default:**

```json
true
```

---

#### coq_settings.completion.replace_prefix_threshold

Controls when inexact match occurs between the text under cursor, and the text to be inserted.

Depending on if the ending of the text under cursor matches the beginning of the text to be inserted, `coq.nvim` will either replace the text under cursor, or chop off the front of some portion of the text to be inserted.

This is the minimum number of characters matched before `coq.nvim` will consider performing any chopping.

**default:**

```json
3
```

#### coq_settings.completion.replace_suffix_threshold

See above.

**default:**

```json
2
```

#### coq_settings.completion.smart

Tries (even harder) to reconcile differences between document and modifications.

Currently used only for slower but better cache algorithm for certain LSPs.

**default:**

```json
true
```

#### coq_settings.completion.skip_after

Set of tokens that should prevent auto completion, when found directly before the cursor.

ie `["{", "}", "[", "]"]`, etc

Setting this to `[""]` will disable auto complete.

**default:**

```json
[]
```
