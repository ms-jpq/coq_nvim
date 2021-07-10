SELECT
  line
FROM lines
WHERE
  buffer_id = :buffer_id
  AND
  line_num >= :lo
  AND
  CASE
    WHEN :hi > 0 THEN line_num < :hi
    ELSE TRUE
  END
ORDER BY
  line_num
