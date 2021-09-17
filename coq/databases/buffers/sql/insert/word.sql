INSERT OR IGNORE INTO words (line_id,  word,  word_start,          lword)
VALUES                      (:line_id, :word, X_WORD_START(:word), LOWER(:word))
