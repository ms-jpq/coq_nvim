SELECT
  tags.name     AS name,
  tags.text     AS text,
  tags.filename AS filename,
  tags.line_num AS line_num
FROM tags
JOIN files
ON files.filename = tags.filename
WHERE
  X_NORMALIZE(:word) <> ''
  AND
  files.filetype = X_NORMALIZE(:filetype)
  tags.lname LIKE X_LIKE_ESC(X_LOWER(X_NORMALIZE(:word)), '!') ESCAPE '!'
  AND
  NOT INSTR(:word, tags.lname)

