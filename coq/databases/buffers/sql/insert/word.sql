INSERT OR IGNORE INTO words (line_id,  word,  lword)
VALUES                      (:line_id, :word, LOWER(:word))
