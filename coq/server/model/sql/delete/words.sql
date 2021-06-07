DELETE FROM words
WHERE
  EXISTS (
    SELECT
      TRUE
    FROM word_locations
    WHERE
      word_locations.filename = :filename
      AND
      word_locations.word = words.word
      AND
      word_locations.line_num >= :lo
      AND
      word_locations.line_num < :hi
  )
