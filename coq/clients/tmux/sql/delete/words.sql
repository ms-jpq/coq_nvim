DELETE FROM words
WHERE
  pane_id NOT IN (:pane_ids)
