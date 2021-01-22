SELECT
  word
FROM
  words
WHERE
  SUBSTR(:q_nword, 1, :match_len) = SUBSTR(nword, 1, :match_len)
  AND
  NOT INSTR(:q_word, word)
