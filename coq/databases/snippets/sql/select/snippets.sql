SELECT
  grammar,
  word,
  snippet,
  label,
  doc
FROM snippets_view
WHERE
  snippet <> ''
  AND
  word <> ''
  AND
  (
    (
      :word <> ''
      AND 
      lword LIKE :like_word ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:word)
      AND
      NOT INSTR(:word, word)
      AND
      X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
    )
    OR
    (
      :sym <> ''
      AND 
      lword LIKE :like_sym ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:sym)
      AND
      NOT INSTR(:sym, word)
      AND
      X_SIMILARITY(LOWER(:sym), lword, :look_ahead) > :cut_off
    )
  )
GROUP BY
  snippet_id
LIMIT :limit
