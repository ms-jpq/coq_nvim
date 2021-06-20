SELECT
  match
FROM matches
WHERE
  snippet_id = :snippet_id
  AND
  matches.lmatch LIKE X_LIKE_ESC(X_LOWER(X_NORM(:word))) ESCAPE '!'
LIMIT 1
