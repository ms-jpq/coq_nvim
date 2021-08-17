SELECT
  grammar,
  prefix,
  snippet,
  label,
  doc
FROM snippets_view
WHERE
  :word <> ''
  AND 
  LENGTH(prefix) * 2 >= LENGTH(:word)
  AND
  ft_src = :filetype
  AND
  lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(:word), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
