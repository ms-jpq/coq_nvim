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
  IIF(tags.word_start, :word, :sym) <> ''
  AND 
  LENGTH(tags.name) + :look_ahead >= LENGTH(IIF(tags.word_start, :word, :sym))
  AND
  files.filetype = :filetype
  AND
  tags.lname LIKE X_LIKE_ESC(SUBSTR(LOWER(IIF(tags.word_start, :word, :sym)), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(IIF(tags.word_start, :word, :sym), tags.name)
  AND
  X_SIMILARITY(LOWER(IIF(tags.word_start, :word, :sym)), tags.lname, :look_ahead) > :cut_off
LIMIT :limit
