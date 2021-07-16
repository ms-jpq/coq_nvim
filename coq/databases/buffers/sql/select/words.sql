SELECT DISTINCT
  word,
  sort_by
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
  lword LIKE X_LIKE_ESC(LOWER(SUBSTR(:word, 1, :exact))) ESCAPE '!'
  AND
  NOT INSTR(:word, word)
  AND
  X_SIMILARITY(LOWER(:word), lword) > :cut_off
LIMIT :limit
