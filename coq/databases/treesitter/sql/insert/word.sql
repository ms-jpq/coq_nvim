INSERT OR IGNORE INTO words (word,  word_start,          lword,        kind,  pword,  pkind,  gpword,  gpkind)
VALUES                      (:word, X_WORD_START(:word), LOWER(:word), :kind, :pword, :pkind, :gpword, :gpkind)
