DELETE FROM words
WHERE
  filename = :filename
  AND
  CASE
    WHEN :hi > 0
      THEN line_num >= :lo
      AND
      line_num < :hi
    ELSE
      TRUE
  END
