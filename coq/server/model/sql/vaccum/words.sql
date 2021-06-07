DELETE FROM words
WHERE
  NOT EXISTS (
    SELECT
      TRUE
    FROM word_locations
    WHERE
      word_locations.word = words.word
  )
