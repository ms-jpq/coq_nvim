SELECT
  suggestions.rowid AS suggestions_id,
  suggestions.source_id <> ? AS cached,
  sources.name AS source,
  sources.short_name AS source_shortname,
  suggestions.label AS label,
  suggestions.sortby AS sortby,
  suggestions.kind AS kind,
  suggestions.doc AS doc,
  suggestions.match AS match,
  suggestions.match_normalized as match_normalized,
  suggestions.ensure_unique AS ensure_unique
FROM suggestions
JOIN sources
ON
  sources.rowid = suggestions.source_id
WHERE
  suggestions.batch_id = ?
  OR
  (
    sources.use_cache
    AND
    suggestions.match_normalized LIKE ?
  )
