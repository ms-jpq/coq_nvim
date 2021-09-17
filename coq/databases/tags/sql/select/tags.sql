SELECT
  tags.`path`,
  tags.line,
  tags.kind,
  tags.name,
  tags.lname,
  tags.pattern,
  tags.typeref,
  tags.scope,
  tags.scopeKind,
  tags.`access`
FROM tags
JOIN files
ON files.filename = tags.`path`
WHERE
  tags.name <> ''
  AND
  X_PICK_WS(word, :word, :sym) <> ''
  AND 
  LENGTH(tags.name) + :look_ahead >= LENGTH(X_PICK_WS(word, :word, :sym))
  AND
  files.filetype = :filetype
  AND
  tags.lname LIKE X_LIKE_ESC(SUBSTR(LOWER(X_PICK_WS(word, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(X_PICK_WS(word, :word, :sym), tags.name)
  AND
  X_SIMILARITY(LOWER(X_PICK_WS(word, :word, :sym)), tags.lname, :look_ahead) > :cut_off
LIMIT :limit
