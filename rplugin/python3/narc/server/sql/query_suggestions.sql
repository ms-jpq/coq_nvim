SELECT
FROM suggestions
JOIN filetypes
ON
  filetypes.rowid = suggestions.filetype_id
WHERE
  filetypes.filetype = ?
  AND
  suggestions.match_normalized LIKE ?
  AND
  suggestions.match <> ?
