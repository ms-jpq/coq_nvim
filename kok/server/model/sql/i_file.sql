REPLACE INTO files (filename, filetype_id)
SELECT
  ?           AS filename,
  filetype_id AS filetype_id
FROM filetypes
WHERE
  filetype = ?

