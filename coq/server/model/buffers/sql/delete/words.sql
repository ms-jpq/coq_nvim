DELETE FROM words
WHERE
  filename = X_NORMALIZE(:filename)
  AND
  line_num >= :lo
  AND
  CASE
    WHEN :hi > 0 THEN line_num < :hi
    ELSE TRUE
  END
