UPDATE files
SET filetype = X_NORMALIZE(:filetype)
WHERE
  filename = X_NORMALIZE(:filename)
