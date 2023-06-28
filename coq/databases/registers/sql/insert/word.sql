INSERT OR IGNORE INTO words (register,   word, lword)
VALUES                      (:register, :word, LOWER(:word))
