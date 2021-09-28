INSERT OR IGNORE INTO matches (snippet_id,  word,  lword)
VALUES                        (:snippet_id, :word, LOWER(:word))
