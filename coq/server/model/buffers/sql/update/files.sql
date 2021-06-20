UPDATE files
SET filetype = X_NORM(:filetype)
WHERE
  filename = X_NORM(:filename)
