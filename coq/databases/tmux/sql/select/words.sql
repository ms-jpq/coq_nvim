SELECT DISTINCT
  word
FROM words
WHERE
  :word <> ''
  AND
  pane_id <> :pane_id
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
LIMIT :limit
