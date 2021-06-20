SELECT DISTINCT
  word
FROM words
WHERE
  X_NORM(:word) <> ''
  AND
  lword LIKE X_LIKE_ESC(X_LOWER(X_NORM(:word))) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
