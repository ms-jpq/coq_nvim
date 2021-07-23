# Fuzzy

## Algorithms

## Conf

### coq_settings.match

These control the matching & scoring algorithms

#### `coq_settings.match.unifying_chars`

These characters count as part of words.

**default:**

```json
["-", "_"]
```

#### `coq_settings.match.max_results`

Maximum number of results to return.

**default:**

```json
33
```

#### `coq_settings.match.context_lines`

How many lines to use, for the purpose of proximity bonus.

**default:**

```json
16
```

#### `coq_settings.match.exact_matches`

For word searching, how many exact prefix characters is required.

**default:**

```json
2
```

#### `coq_settings.match.look_ahead`

For word searching, how many characters to look ahead, incase of typos.

**default:**

```json
2
```

#### `coq_settings.match.fuzzy_cutoff`

What is the minimum similarity score, for a word to be proposed by the algorithm.

**default:**

```json
0.6
```

### coq_settings.weights

#### `coq_settings.weights.prefix_matches`

**default:**

```json
2.0
```

#### `coq_settings.weights.edit_distance`

**default:**

```json
1.5
```

#### `coq_settings.weights.insertion_order`

**default:**

```json
1.0
```

#### `coq_settings.weights.neighbours`

**default:**

```json
0.5
```

