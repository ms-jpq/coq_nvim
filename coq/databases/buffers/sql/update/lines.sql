UPDATE lines
SET
  line_num = line_num + :shift
WHERE
  buffer_id = :buffer_id
  AND
  line_num >= :lo
