SELECT
  word
FROM
  words
WHERE
  nword LIKE ? ESCAPE '!',
  AND
  NOT INSTR(?, word)
