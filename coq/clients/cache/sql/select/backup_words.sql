WITH sort_bys AS (
  SELECT
    word,
    SUBSTR(lword, INSTR(lword, LOWER(:word))) as sort_by
  FROM words
  WHERE
    word <> ''
    AND
    sort_by <> word
)
SELECT
  word,
  sort_by
FROM sort_bys
WHERE
  :word <> ''
  AND
  X_SIMILARITY(LOWER(:word), sort_by, :look_ahead) > :cut_off
LIMIT :limit
