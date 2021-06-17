SELECT DISTINCT
  word
FROM words
WHERE
  :word <> ''
  AND
  pane_id <> :pane_id
  AND
  lword LIKE X_LIKE_ESC(X_LOWER(:word)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)

