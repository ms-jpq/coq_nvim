DELETE FROM files
WHERE
  filename NOT IN (${filenames})
