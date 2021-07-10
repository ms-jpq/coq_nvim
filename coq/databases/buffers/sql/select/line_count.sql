SELECT
  COALESCE(MAX(line_num), -1) + 1 AS line_count
FROM lines
WHERE
  buffer_id = :buffer_id

