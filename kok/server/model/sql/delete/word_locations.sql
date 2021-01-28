DELETE FROM word_locations
WHERE
  line_num >= :lo
  AND
  line_num < :hi
