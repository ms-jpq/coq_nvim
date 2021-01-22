DELETE
FROM words
WHERE
  NOT EXISTS (
    SELECT
      NULL
    FROM word_locations
    WHERE
      word_locations.word_id = words.rowid
  )
