SELECT
  match,
  match_normalized,
  label,
  sortby,
  kind,
  doc
FROM suggestions
JOIN filetypes
ON
  filetypes.rowid = suggestions.filetype_id
WHERE
  filetypes.filetype = ?
  AND
  suggestions.match_normalized LIKE ? ESCAPE '!'
  AND
  suggestions.match <> ?
