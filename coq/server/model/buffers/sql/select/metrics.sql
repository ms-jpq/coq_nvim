SELECT
  tmp_for_metrics.word                           AS word,
  COALESCE(filetype_wordcount_view.wordcount, 0) AS wordcount,
  COALESCE(insertions.rowid, 0)                  AS insert_order
FROM tmp_for_metrics
LEFT JOIN filetype_wordcount
ON
  filetype_wordcount_view.word = tmp_for_metrics.word
LEFT JOIN insertions
ON
  insertions.content = word
ORDER BY
  tmp_for_metrics.rowid
