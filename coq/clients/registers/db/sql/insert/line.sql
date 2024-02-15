INSERT OR IGNORE INTO lines (register,  line,  word,  lword)
VALUES                      (:register, :line, :word, LOWER(:word))

