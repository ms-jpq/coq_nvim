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
    ELSE TRUE
  END
  AND
  :word <> ''
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(:word) 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
LIMIT :limit
