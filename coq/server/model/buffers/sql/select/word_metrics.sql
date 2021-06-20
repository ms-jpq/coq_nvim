WITH q1 AS (
  SELECT
    COALESCE(MAX(rowid), 0) AS insertion_order
  FROM insertions
  WHERE
    content = X_NORM(:word)
), q2 AS (
  SELECT
    COUNT(*) AS ft_count
  FROM words
  JOIN files
  ON
    files.filename = words.filename
  WHERE
    files.filetype = X_NORM(:filetype)
    AND
    words.word = :word
), q3 AS (
  SELECT
    :lines_tot - COALESCE(MIN(ABS(words.line_num - :line_num)), :lines_tot) AS line_diff
  FROM words
  JOIN files
  ON
    files.filename = words.filename
  WHERE
    files.filename = X_NORM(:filename)
    AND
    words.word = X_NORM(:word)
)
SELECT
  q1.insertion_order AS insertion_order,
  q2.ft_count AS ft_count,
  q3.line_diff AS line_diff
FROM q1
JOIN q2
JOIN q3
