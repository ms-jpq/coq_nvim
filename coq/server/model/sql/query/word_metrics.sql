WITH q1 AS (
  SELECT
    COALESCE(MAX(rowid), -1) AS insertion_order
  FROM insertions
  WHERE
    content = :word
), q2 AS (
  SELECT
    COUNT(*) AS ft_count
  FROM word_locations
  JOIN files
  ON
    files.filename = word_locations.filename
  WHERE
    files.project = :project
    AND
    files.filetype = :filetype
    AND
    word_locations.word = :word
), q3 AS (
  SELECT
    COALESCE(MIN(ABS(word_locations.line_num - :line_num)), 10000) AS line_diff
  FROM word_locations
  JOIN files
  ON
    files.filename = word_locations.filename
  WHERE
    files.filename = :filename
    AND
    word_locations.word = :word
),
SELECT
  q1.insertion_order,
  q2.ft_count,
  q3.line_diff
FROM q1
JOIN q2
JOIN q3
