INSERT OR IGNORE INTO words (pane_id,  word,  word_start,          lword)
VALUES                      (:pane_id, :word, X_WORD_START(:word), LOWER(:word))
