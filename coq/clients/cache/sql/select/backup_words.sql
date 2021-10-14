WITH short_words AS (
  SELECT
    SUBSTR(lword, INSTR(lword, LOWER(:word))) as short_word
  FROM words
  WHERE
    word <> ''
    AND
    short_word <> word
)
SELECT
  short_word
FROM short_words
WHERE
  :word <> ''
  AND
  X_SIMILARITY(LOWER(:word), short_word, :look_ahead) > :cut_off
LIMIT :limit
