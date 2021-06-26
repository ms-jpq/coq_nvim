SELECT
  COALESCE(MAX(line_num), 0) AS lines_tot
FROM words
WHERE
  filename = X_NORMALIZE(:filename)

