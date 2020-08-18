SELECT
  suggestions.rowid AS suggestions_id,
  batches.p_row AS p_row,
  batches.p_col AS p_col,
  suggestions.source_id <> ? AS cached,
  sources.name AS source,
  sources.short_name AS source_shortname,
  sources.priority AS priority,
  suggestions.label AS label,
  suggestions.sortby AS sortby,
  suggestions.kind AS kind,
  suggestions.doc AS doc,
  suggestions.match AS match,
  suggestions.match_normalized as match_normalized,
  sources.ensure_unique AS ensure_unique
FROM suggestions
JOIN sources
ON
  sources.rowid = suggestions.source_id
JOIN batches
ON
  batches.rowid = suggestions.batch_id
WHERE
  batches.rowid = ?
  OR
  (
    sources.use_cache
    AND
    suggestions.match_normalized LIKE ?
  )
