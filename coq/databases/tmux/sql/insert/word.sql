INSERT OR IGNORE INTO words (pane_id,  word,  lword)
VALUES                      (:pane_id, :word, LOWER(:word))
