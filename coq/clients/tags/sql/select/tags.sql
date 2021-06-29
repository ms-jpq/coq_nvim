SELECT
  tags.name,
  tags.lname,
  tags.pattern,
  tags.roles,
  tags.kind,
  tags.typeref,
  tags.scope,
  tags.scopeKind,
  tags.`access`

FROM tags
JOIN files
ON files.filename = tags.filename
WHERE
  X_NORMALIZE(:word) <> ''
  AND
  files.filetype = X_NORMALIZE(:filetype)
  AND
  tags.lname LIKE X_LIKE_ESC(X_LOWER(X_NORMALIZE(SUBSTR(:word, 1, :exact)))) ESCAPE '!'
  AND
  NOT INSTR(:word, tags.lname)
  AND
  X_SIMILARITY(X_LOWER(X_NORMALIZE(SUBSTR(:word, 1, :exact))), tags.lname) > :cut_off
ORDER BY
  tags.filename = :filename DESC,
  ABS(tags.line_num - :line_num)
