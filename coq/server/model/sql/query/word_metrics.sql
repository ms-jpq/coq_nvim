SELECT
  w_count,
  line_num
FROM
  word_metrics_view
WHERE
  word = :word
  AND
  filename = :filename

