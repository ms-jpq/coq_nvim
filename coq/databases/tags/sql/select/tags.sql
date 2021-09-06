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
  :word <> ''
  AND
  tags.name <> ''
  AND 
  LENGTH(tags.name) + :look_ahead >= LENGTH(:word)
  AND
  files.filetype = :filetype
  AND
  tags.lname LIKE X_LIKE_ESC(SUBSTR(LOWER(:word), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(:word, tags.name)
  AND
  X_SIMILARITY(LOWER(:word), tags.lname, :look_ahead) > :cut_off
LIMIT :limit
