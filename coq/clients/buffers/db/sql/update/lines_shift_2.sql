UPDATE lines
SET
  line_num = -line_num
WHERE
  buffer_id = :buffer_id
  AND
  line_num < 0
