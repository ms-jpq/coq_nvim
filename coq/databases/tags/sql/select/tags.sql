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
  CASE WHEN tags.word_start THEN :word ELSE :sym END <> ''
  AND 
  LENGTH(tags.name) + :look_ahead >= LENGTH(CASE WHEN tags.word_start THEN :word ELSE :sym END)
  AND
  files.filetype = :filetype
  AND
  tags.lname LIKE X_LIKE_ESC(SUBSTR(LOWER(CASE WHEN tags.word_start THEN :word ELSE :sym END), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(CASE WHEN tags.word_start THEN :word ELSE :sym END, tags.name)
  AND
  X_SIMILARITY(LOWER(CASE WHEN tags.word_start THEN :word ELSE :sym END), tags.lname, :look_ahead) > :cut_off
LIMIT :limit
