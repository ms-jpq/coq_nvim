SELECT
  word
FROM words
WHERE
  word <> ''
  AND
  CASE WHEN word_start THEN :word ELSE :sym END <> ''
  AND 
  LENGTH(word) + :look_ahead >= LENGTH(CASE WHEN word_start THEN :word ELSE :sym END)
  AND
  lword LIKE X_LIKE_ESC(SUBSTR(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), 1, :exact)) ESCAPE '!'
  AND
  NOT INSTR(CASE WHEN word_start THEN :word ELSE :sym END, word)
  AND
  X_SIMILARITY(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), lword, :look_ahead) > :cut_off

LIMIT :limit
