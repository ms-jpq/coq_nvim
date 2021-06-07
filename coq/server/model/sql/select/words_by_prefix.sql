SELECT DISTINCT
  word
FROM words
WHERE
  filename LIKE X_LIKE_ESC(:cwd) ESCAPE '!'
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(:lword, 1, :prefix_len)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
