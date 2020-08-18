DELETE FROM suggestions
WHERE
  rowid IN (
    SELECT
      suggestions.rowid
    FROM suggestions
    JOIN sources
    ON
      sources.rowid = suggestions.source_id
    WHERE
      sources.use_cache = 0
  )
