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
  (
    (
      :word <> ''
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
    )
    OR
    (
      :sym <> ''
      AND 
      LENGTH(tags.name) + :look_ahead >= LENGTH(:sym)
      AND
      files.filetype = :filetype
      AND
      tags.lname LIKE X_LIKE_ESC(SUBSTR(LOWER(:sym), 1, :exact)) ESCAPE '!'
      AND
      NOT INSTR(:sym, tags.name)
      AND
      X_SIMILARITY(LOWER(:sym), tags.lname, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
