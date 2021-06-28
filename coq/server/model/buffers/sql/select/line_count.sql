SELECT
  COALESCE(MAX(line_num), 0) AS line_count
FROM lines
WHERE
  filename = X_NORMALIZE(:filename)

