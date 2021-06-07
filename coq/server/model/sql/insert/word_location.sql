REPLACE INTO word_locations (filename,  word,          line_num)
VALUES                      (:filename, X_NORM(:word), :line_num)
