SELECT
  word
FROM
  words
WHERE
  lword LIKE (REPLACE(REPLACE(REPLACE(SUBSTR(:lword, 1, :prefix_len), '!', '!!'), '%', '!%'), '_', '!_') || '%') ESCAPE '!'
  AND
  NOT INSTR(:word, word)
