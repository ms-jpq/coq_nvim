SELECT
  key,
  word
FROM words
WHERE
  word <> ''
  AND
  (
    (
      lword LIKE :like_word ESCAPE '!'
      AND
      LENGTH(word) + :look_ahead >= LENGTH(:word)
      AND
      X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
    )
    OR
    (
      lword LIKE :like_sym ESCAPE '!'
      AND
      LENGTH(word) + :look_ahead >= LENGTH(:sym)
      AND
      X_SIMILARITY(LOWER(:sym), lword, :look_ahead) > :cut_off
    )
  )
GROUP BY
  key
LIMIT :limit
