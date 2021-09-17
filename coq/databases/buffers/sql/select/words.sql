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
  IIF(word_start, :word, :sym) <> ''
  AND 
  LENGTH(word) + :look_ahead >= LENGTH(IIF(word_start, :word, :sym))
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(IIF(word_start, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(IIF(word_start, :word, :sym), word)
  AND
  X_SIMILARITY(LOWER(IIF(word_start, :word, :sym)), lword, :look_ahead) > :cut_off

LIMIT :limit
