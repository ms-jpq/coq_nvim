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
  (
    (
      :word <> ''
      AND 
      LENGTH(prefix) + :look_ahead >= LENGTH(:word)
      AND
      ft_src = :filetype
      AND
      lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
      AND
      X_SIMILARITY(LOWER(:word), lprefix, :look_ahead) > :cut_off
    )
    OR
    (
      :sym <> ''
      AND 
      LENGTH(prefix) + :look_ahead >= LENGTH(:sym)
      AND
      ft_src = :filetype
      AND
      lprefix LIKE X_LIKE_ESC(SUBSTR(LOWER(:sym), 1, :exact)) ESCAPE '!'
      AND
      X_SIMILARITY(LOWER(:sym), lprefix, :look_ahead) > :cut_off
    )
  )
GROUP BY
  snippet_id
LIMIT :limit
