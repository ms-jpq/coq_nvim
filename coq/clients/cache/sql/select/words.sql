SELECT
  word
FROM words
WHERE
  word <> ''
  AND
  (
    (
      :word <> ''
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:word)
      AND
      lword LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
      AND
      NOT INSTR(:word, word)
      AND
      X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
    )
  OR
    (
      :sym <> ''
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:sym)
      AND
      lword LIKE X_LIKE_ESC(SUBSTR(LOWER(:sym), 1, :exact)) ESCAPE '!'
      AND
      NOT INSTR(:sym, word)
      AND
      X_SIMILARITY(LOWER(:sym), lword, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
