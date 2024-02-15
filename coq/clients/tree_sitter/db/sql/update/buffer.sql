UPDATE buffers
SET
  filetype = :filetype,
  filename = :filename
WHERE
  rowid = :rowid
