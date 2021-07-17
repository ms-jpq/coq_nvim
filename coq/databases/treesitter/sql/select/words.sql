SELECT DISTINCT
  word,
  kind
FROM words
WHERE
  :word <> ''
  AND
  lword LIKE X_LIKE_ESC(LOWER(SUBSTR(:word, 1, :exact))) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(LOWER(:word), lword) > :cut_off
LIMIT :limit
