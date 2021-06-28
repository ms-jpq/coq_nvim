UPDATE lines
SET line_num = line_num + :shift
WHERE
  filename = X_NORMALIZE(:filename)
  AND
  line_num >= :lo

