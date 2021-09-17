INSERT OR REPLACE INTO words (word,  word_start,          lword)
VALUES                       (:word, X_WORD_START(:word), LOWER(:word))

