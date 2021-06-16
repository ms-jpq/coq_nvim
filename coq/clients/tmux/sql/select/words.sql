SELECT DISTINCT
  word
FROM words
WHERE
  pane_id <> :pane_id
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(X_LOWER(:word), 1, :prefix_len - 1)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)

