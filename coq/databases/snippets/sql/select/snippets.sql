SELECT
  grammar,
  prefix,
  snippet,
  label,
  doc
FROM snippets_view
WHERE
  snippet <> ''
  AND
  CASE WHEN word_start THEN :word ELSE :sym END <> ''
  AND 
  LENGTH(prefix) + :look_ahead >= LENGTH(CASE WHEN word_start THEN :word ELSE :sym END)
  AND
  ft_src = :filetype
  AND
  lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), 1, :exact)) ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
