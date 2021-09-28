SELECT DISTINCT
  word,
  kind,
  pword,
  pkind,
  gpword,
  gpkind
FROM words
WHERE
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
LIMIT :limit
