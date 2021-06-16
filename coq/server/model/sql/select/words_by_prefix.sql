SELECT DISTINCT
  word
FROM words
WHERE
  filename LIKE X_LIKE_ESC(:cwd) ESCAPE '!'
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(X_LOWER(:word), 1, :prefix_len - 1)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
