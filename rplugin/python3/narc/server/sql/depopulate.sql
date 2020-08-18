DELETE FROM suggestions
WHERE
  suggestions.rowid IN (
    SELECT
      suggestions.rowid
    FROM suggestions
    JOIN sources
    ON
      sources.rowid = suggestions.source_id
    WHERE
      sources.use_cache = 0
  )
