SELECT DISTINCT
  word
FROM words
WHERE
  :word <> ''
  AND
  filename LIKE X_LIKE_ESC(:cwd) ESCAPE '!'
  AND
  lword LIKE X_LIKE_ESC(X_LOWER(:word)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
