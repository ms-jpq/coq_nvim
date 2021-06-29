SELECT 
  filetype
FROM files
WHERE
  filename = X_NORMALIZE(:filename)


