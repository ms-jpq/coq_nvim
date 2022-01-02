INSERT OR REPLACE INTO words (key,  word,  lword)
VALUES                       (:key, :word, LOWER(:word))
