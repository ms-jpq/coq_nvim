SELECT
  kind,
  kind_name,
  match,
  content,
  label,
  doc
FROM query_view
WHERE
  filetype = ?
AND
  match LIKE ?
