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
  IIF(word_start, :word, :sym) <> ''
  AND 
  LENGTH(prefix) + :look_ahead >= LENGTH(IIF(word_start, :word, :sym))
  AND
  ft_src = :filetype
  AND
  lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(IIF(word_start, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(IIF(word_start, :word, :sym)), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
