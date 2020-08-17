WHERE
  NOT suggestions.use_cache
  OR
  suggestions.batch_id = ?
UNION ALL
