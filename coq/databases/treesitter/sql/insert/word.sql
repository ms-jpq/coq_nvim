INSERT OR IGNORE INTO words ( word, lword,         kind)
VALUES                      (:word, LOWER(:word), :kind)
