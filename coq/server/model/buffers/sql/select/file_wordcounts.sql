SELECT
  tmp_for_metrics.word                      AS word,
  COALESCE(filetype_wordcount.wordcount, 0) AS wordcount
FROM tmp_for_metrics
LEFT JOIN filetype_wordcount
ON
  filetype_wordcount.word = tmp_for_metrics.word
ORDER BY
  tmp_for_metrics.rowid
