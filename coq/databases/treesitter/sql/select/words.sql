SELECT DISTINCT
  word,
  kind,
  pword,
  pkind,
  gpword,
  gpkind
FROM words_view
WHERE
  buf_id = :buf_id
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
      word <> SUBSTR(:word, 1, LENGTH(word))
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
      word <> SUBSTR(:sym, 1, LENGTH(word))
      AND
      X_SIMILARITY(LOWER(:sym), lword, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
