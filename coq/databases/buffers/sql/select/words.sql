SELECT
  words.word,
  buffers.filetype,
  buffers.filename,
  lines.line_num
FROM buffers
JOIN lines
  ON lines.buffer_id = buffers.rowid
JOIN words
  ON words.line_id = lines.rowid
GROUP BY
  words.word
HAVING
  CASE
    WHEN :filetype <> NULL THEN buffers.filetype = :filetype
    ELSE 1
  END
  AND
  word <> ''
  AND
  (
    (
      :word <> ''
      AND 
      lword LIKE :like_word ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:word)
      AND
      word <> SUBSTR(:word, 1, LENGTH(word))
      AND
      X_SIMILARITY(LOWER(:word), lword, :look_ahead) > :cut_off
    )
    OR
    (
      :sym <> ''
      AND 
      lword LIKE :like_sym ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:sym)
      AND
      word <> SUBSTR(:sym, 1, LENGTH(word))
      AND
      X_SIMILARITY(LOWER(:sym), lword, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
