SELECT
  word
FROM words
WHERE
  lword LIKE X_LIKE_ESC(SUBSTR(:lword, 1, :prefix_len)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
