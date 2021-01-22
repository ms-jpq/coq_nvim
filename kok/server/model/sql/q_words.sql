SELECT
  word
FROM
  words
WHERE
  nword LIKE (REPLACE(REPLACE(REPLACE(SUBSTR(:q_nword, 1, :match_len), '!', '!!'), '%', '!%'), '_', '!_') || '%') ESCAPE '!'
  AND 
  NOT :q_word LIKE _test ESCAPE '!'
