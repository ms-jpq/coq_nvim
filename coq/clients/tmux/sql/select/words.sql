SELECT DISTINCT
  word
FROM words
WHERE
  LENGTH(:word) >= :prefix_len
  AND
  pane_id <> :pane_id
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(X_LOWER(:word), 1, :prefix_len)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)

