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
  prefix <> ''
  AND
  CASE WHEN word_start THEN :word ELSE :sym END <> ''
  AND 
  LENGTH(prefix) + :look_ahead >= LENGTH(CASE WHEN word_start THEN :word ELSE :sym END)
  AND
  ft_src = :filetype
  AND
  lprefix LIKE CASE WHEN word_start THEN :like_word ELSE :like_sym END ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
