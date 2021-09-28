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
      tags.lname LIKE :like_word ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:word)
      AND
      NOT INSTR(:word, tags.name)
      AND
      X_SIMILARITY(LOWER(:word), tags.lname, :look_ahead) > :cut_off
    )
    OR
    (
      :sym <> ''
      AND 
      tags.lname LIKE :like_sym ESCAPE '!'
      AND 
      LENGTH(word) + :look_ahead >= LENGTH(:sym)
      AND
      NOT INSTR(:sym, tags.name)
      AND
      X_SIMILARITY(LOWER(:sym), tags.lname, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
