REPLACE INTO files (filename, filetype_id)
SELECT
  :filename   AS filename,
  filetype_id AS filetype_id
FROM filetypes
WHERE
  filetype = :filetype

