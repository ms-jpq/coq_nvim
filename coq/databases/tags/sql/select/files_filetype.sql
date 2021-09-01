SELECT 
  filetype
FROM files
WHERE
  filename = X_NORM_CASE(:filename)
