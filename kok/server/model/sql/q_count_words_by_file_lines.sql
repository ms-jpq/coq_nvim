SELECT
  w_count,
  line_num
FROM
  count_words_by_file_lines_view
WHERE
  word = :word
  AND
  filename = :filename

