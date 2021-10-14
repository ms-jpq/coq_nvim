SELECT
  word
FROM words
WHERE
  word <> ''
  AND
  :word <> ''
  AND
  X_SIMILARITY(LOWER(:word), SUBSTR(lword, INSTR(lword, LOWER(:word))), :look_ahead) > :cut_off
LIMIT :limit
