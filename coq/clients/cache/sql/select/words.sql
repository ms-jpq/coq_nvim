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
  lword LIKE CASE WHEN word_start THEN :like_word ELSE :like_sym END ESCAPE '!'
  AND
  NOT INSTR(CASE WHEN word_start THEN :word ELSE :sym END, word)
  AND
  X_SIMILARITY(LOWER(CASE WHEN word_start THEN :word ELSE :sym END), lword, :look_ahead) > :cut_off

LIMIT :limit
