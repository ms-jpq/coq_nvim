# Misc

### coq_settings.limits

Various timeouts and retry limits

#### `coq_settings.limits.index_cutoff`

Buffers above this size will not be indexed.

**default:**

```json
333333
```

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
0.088
```

#### `coq_settings.limits.completion_manual_timeout`

Timeout for manual completions. ie. user pressing `<c-space>`, or whatever custom hotkey.

**default:**

```json
0.66
```

#### `coq_settings.limits.download_retries`

How many attempts to download Tabnine, should previous attempts fail.

**default:**

```json
6
```

#### `coq_settings.limits.download_timeout`

Tabnine download timeout.

**default:**

```json
66
```
