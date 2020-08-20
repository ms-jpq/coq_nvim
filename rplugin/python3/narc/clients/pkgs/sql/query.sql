SELECT
  word
FROM words
WHERE
  nword LIKE ?
  AND
  nword <> ?
