SELECT
  word
FROM
  words
WHERE
  nword LIKE (REPLACE(SUBSTR(:q_nword, 1, :match_len), '!', '!!') || '%') ESCAPE '!'
  AND
  NOT :q_word LIKE _test ESCAPE '!'
