SELECT DISTINCT
  word
FROM words
JOIN lines
ON lines.rowid = words.line_id
JOIN buffers
ON buffers.rowid = lines.buffer_id
WHERE
  CASE
    WHEN :filetype <> NULL THEN buffers.filetype = :filetype
    ELSE 1
  END
  AND
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
