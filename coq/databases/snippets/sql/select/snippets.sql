SELECT
  grammar,
  prefix,
  snippet,
  label,
  doc
FROM snippets_view
LEFT JOIN enabled_sources
ON
  enabled_sources.source = snippets_view.source_id
WHERE
  CASE
    WHEN NOT (SELECT COUNT(*) FROM enabled_sources) THEN 1
    ELSE enabled_sources.source <> NULL
  END
  AND
  :word <> ''
  AND 
  LENGTH(prefix) + :look_ahead >= LENGTH(:word)
  AND
  ft_src = :filetype
  AND
  lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(:word), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
