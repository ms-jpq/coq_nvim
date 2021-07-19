SELECT
  rowid
FROM words
WHERE
  :word <> ''
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(:word) 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
LIMIT :limit
