SELECT
  w_count
FROM
  count_words_by_filetype_view
WHERE
  word = :word
  AND
  filetype = :filetype
