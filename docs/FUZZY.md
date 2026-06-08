# Fuzzy

## Algorithms

`coq.nvim` uses ensemble ranking. It uses a two stage Filter -> Rank system.

Both stages uses a `look_ahead` parameter to adjust for typos.

### Stage 1 - Filtering

All `sqlite` based sources will require some `exact_matches` number of prefix matches.

This is done to reduce the non-indexed search space.

A quick multiset based filter is computed on the candidates, resulting in a normalized `[0..1]` score.

Results that do not score above the `fuzzy_cutoff` are dropped at this stage.

### Stage 2 - Ranking

On a reduced search set, a more comprehensive ensemble score is computed for each candidate.

The primary metrics are `prefix_matches`, `edit_distance`, `recency` and `proximity`.

For each metric, the relative rank of each candidate among their peers is weight adjusted.

All the primary metrics are summed together in a weighted average, and rounded to an integer `[0..1000]`.

Lexicographical sorting is then applied with secondary metrics such as `presence of imports`, `presence of documentation`, etc serving as tie breakers.

## Conf

`coq_settings.match`

`coq_settings.weights`

---

### coq_settings.match

These control the matching & scoring algorithms

#### `coq_settings.match.max_results`

Maximum number of results to return.

**default:**

```json
33
```

#### `coq_settings.match.exact_matches`

For word searching, how many exact prefix characters is required.

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

---

### coq_settings.weights

#### `coq_settings.weights.recency`

Relative weight adjustment of recently inserted items.

**default:**

```json
1.0
```

#### `coq_settings.weights.proximity`

Relative weight adjustment of prevalence in nearby lines.

**default:**

```json
0.5
```
