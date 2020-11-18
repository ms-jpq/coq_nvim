SELECT
  match,
  match_normalized,
  priority,
  label,
  sortby,
  kind,
  doc
FROM suggestions
WHERE
  filetype = ?
  AND
  match_normalized LIKE ? ESCAPE '!'
  AND
  match <> ?
