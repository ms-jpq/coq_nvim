SELECT
  suggestions.match,
  suggestions.match_normalized,
  suggestions.priority,
  suggestions.label,
  suggestions.sortby,
  suggestions.kind,
  suggestions.doc
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
