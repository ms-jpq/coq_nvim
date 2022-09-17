DELETE FROM words
WHERE
  buffer_id = :buffer_id
  AND
  hi >= :lo
  AND
  CASE
    WHEN :hi >= 0 THEN lo < :hi
    ELSE 1
  END
