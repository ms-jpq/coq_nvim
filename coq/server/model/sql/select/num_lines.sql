SELECT
  COALESCE(MAX(line_num), 0) AS num_lines
FROM words
WHERE
  words.filename = :filename

