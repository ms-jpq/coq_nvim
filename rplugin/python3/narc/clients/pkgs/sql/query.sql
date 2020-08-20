SELECT
  word
FROM words
WHERE
  nword LIKE ?
  AND
  word <> ?
ESCAPE '!'
