SELECT
  words.word,
  panes.session_name,
  panes.window_index,
  panes.window_name,
  panes.pane_index,
  panes.pane_title
FROM panes
JOIN words
ON words.pane_id = panes.pane_id
GROUP BY
  words.word
HAVING
  panes.pane_id <> :pane_id
  AND
  words.word <> ''
  AND
  (
    (
      :word <> ''
      AND 
      words.lword LIKE :like_word ESCAPE '!'
      AND 
      LENGTH(words.word) + :look_ahead >= LENGTH(:word)
      AND
      words.word <> SUBSTR(:word, 1, LENGTH(words.word))
      AND
      X_SIMILARITY(LOWER(:word), words.lword, :look_ahead) > :cut_off
    )
    OR
    (
      :sym <> ''
      AND 
      lword LIKE :like_sym ESCAPE '!'
      AND 
      LENGTH(words.word) + :look_ahead >= LENGTH(:sym)
      AND
      words.word <> SUBSTR(:sym, 1, LENGTH(words.word))
      AND
      X_SIMILARITY(LOWER(:sym), words.lword, :look_ahead) > :cut_off
    )
  )
LIMIT :limit
