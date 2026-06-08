# Misc

### coq_settings.limits

#### `coq_settings.limits.idle_timeout`

Background tasks are executed after cursor idling for `updatetime` + `idle_timeout`.

**default:**

```json
1.88
```

#### `coq_settings.limits.completion_auto_timeout`

Soft timeout for on-keystroke completions.

**default:**

```json
0.166
```

#### `coq_settings.limits.completion_manual_timeout`

Timeout for manual completions. ie. user pressing `<c-space>`, or whatever custom hotkey.

**default:**

```json
1.966
```
