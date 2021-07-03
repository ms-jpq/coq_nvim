SELECT DISTINCT
  word,
  sort_by
FROM words
WHERE
  X_NORMALIZE(:word) <> ''
  AND
  pane_id <> :pane_id
  AND
  lword LIKE X_LIKE_ESC(X_LOWER(X_NORMALIZE(SUBSTR(:word, 1, :exact)))) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(X_LOWER(X_NORMALIZE(SUBSTR(:word, 1, :exact))), lword) > :cut_off
