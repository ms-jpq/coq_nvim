# Display

### coq_settings.display

#### `coq_settings.display.mark_highlight_group`

The highlight group alias for snippet regions that you can navigate around using a hotkey.

**default:**

```json
"Pmenu"
```

#### coq_settings.display.pum

Vim calls the completion popup menu _`pum`_.

##### `coq_settings.display.pum.fast_close`

The popup menu will be closed on each keystroke, and re-opened when results coming in.

Disabling this will lead to more smooth menu animation, but also the stale results will be shown until the new one comes in.

**default:**

```json
True
```

##### `coq_settings.display.pum.y_max_len`

Maximum height of the popup menu.

The min of `(y_max_len, y_ratio)` wins.

**default:**

```json
16
```

##### `coq_settings.display.pum.y_ratio`

Maximum height of the popup menu, as a ratio of window height.

**default:**

```json
0.3
```

##### `coq_settings.display.pum.x_max_len`

Maximum width of the popup menu.

**default:**

```json
66
```

##### `coq_settings.display.pum.x_truncate_len`

Omit `<kind>` for snippets when we are out of space.

**default:**

```json
12
```

##### `coq_settings.display.pum.ellipsis`

Show `...` when we are out of space.

**default:**

```json
"…"
```

##### `coq_settings.display.pum.kind_context`

For item `<kind>` show `[<kind>]`, purely for aesthetics.

**default:**

```json
[" [", "]"]
```

##### `coq_settings.display.pum.source_context`

For item `<source>` show `「<source>」`, purely for aesthetics.

**default:**

```json
["「", "」"]
```

#### coq_settings.display.preview

Used for the preview window.

##### `coq_settings.display.preview.x_max_len`

Maximum width.

**default:**

```json
88
```

##### `coq_settings.display.preview.resolve_timeout`

Bit niche, if a completion has documentation, but still be be looked up for further documentation, how long to wait for further documentation to show up.

**default:**

```json
0.09
```

##### `coq_settings.display.preview.positions`

Preferred ordering of preview window.

This is a tie breaker, previews will be shown in the position with most usable-space first.

If you do not like a position, setting it to `null` will disable it entirely.

Setting everything to `null` will disable previews.

**default:**

```json
{ "north": 1, "south": 2, "west": 3, "east": 4 }
```
