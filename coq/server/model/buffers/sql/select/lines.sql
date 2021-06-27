SELECT
  line
FROM lines
WHERE
  filename = X_NORMALIZE(:filename)
ORDER BY
  line_num
