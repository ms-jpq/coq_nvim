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
  X_PICK_WS(word, :word, :sym) <> ''
  AND 
  LENGTH(prefix) + :look_ahead >= LENGTH(X_PICK_WS(word, :word, :sym))
  AND
  ft_src = :filetype
  AND
  lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(X_PICK_WS(word, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  X_SIMILARITY(LOWER(X_PICK_WS(word, :word, :sym)), lprefix, :look_ahead) > :cut_off
GROUP BY
  snippet_id
LIMIT :limit
