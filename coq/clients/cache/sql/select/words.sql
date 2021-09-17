SELECT
  word
FROM words
WHERE
  word <> ''
  AND
  X_PICK_WS(word, :word, :sym) <> ''
  AND 
  LENGTH(word) + :look_ahead >= LENGTH(X_PICK_WS(word, :word, :sym))
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(X_PICK_WS(word, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(X_PICK_WS(word, :word, :sym), word)
  AND
  X_SIMILARITY(LOWER(X_PICK_WS(word, :word, :sym)), lword, :look_ahead) > :cut_off

LIMIT :limit
