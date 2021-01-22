SELECT
  word
FROM
  words
WHERE
  SUBSTR(?, 1, ?) = SUBSTR(nword, 1, ?)
  AND
  NOT INSTR(?, word)
