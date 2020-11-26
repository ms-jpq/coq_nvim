SELECT
  edit
FROM main_view
WHERE
  filename = ?
  AND
  ro = ?
  AND
  min(abs(co - ?), abs(? - co)) < ?